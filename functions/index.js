const {onSchedule} = require("firebase-functions/v2/scheduler");
const {logger} = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();

const DEFAULT_REMINDER_MESSAGE =
  "Your health is calling... Pick up with your meds";
const DEFAULT_REMINDER_INTERVAL = "At exact time";
const DISPATCH_COLLECTION = "reminderDispatches";

exports.sendMedicationReminders = onSchedule(
  {
    schedule: "every 1 minutes",
    timeZone: "Etc/UTC",
    region: "us-central1",
    memory: "256MiB",
    retryCount: 0,
  },
  async () => {
    const nowUtc = new Date();
    const usersSnapshot = await db.collection("users").get();

    let usersScanned = 0;
    let remindersSent = 0;
    let dispatchesSkipped = 0;

    for (const userDoc of usersSnapshot.docs) {
      usersScanned += 1;
      const userId = userDoc.id;

      const [medicationsSnapshot, tokensSnapshot, settingsSnapshot] =
        await Promise.all([
          db.collection("users").doc(userId).collection("medications").get(),
          db
            .collection("users")
            .doc(userId)
            .collection("notificationTokens")
            .get(),
          db
            .collection("users")
            .doc(userId)
            .collection("settings")
            .doc("preferences")
            .get(),
        ]);

      if (medicationsSnapshot.empty || tokensSnapshot.empty) {
        continue;
      }

      const reminderInterval = normalizeReminderInterval(
        settingsSnapshot.data()?.reminderInterval
      );
      const reminderOffsetMinutes = reminderOffsetMinutesFromInterval(
        reminderInterval
      );
      const reminderBody =
        settingsSnapshot.data()?.customReminderMessage?.trim() ||
        DEFAULT_REMINDER_MESSAGE;

      const tokenGroups = groupTokensByOffset(tokensSnapshot.docs);
      if (tokenGroups.size === 0) {
        continue;
      }

      for (const medicationDoc of medicationsSnapshot.docs) {
        const medication = medicationDoc.data();
        if (!isMedicationEligible(medication)) {
          continue;
        }

        const parsedTime = parseMedicationTime(medication.time);
        if (!parsedTime) {
          continue;
        }

        const medicationId = medicationDoc.id;

        for (const [offsetMinutes, tokens] of tokenGroups.entries()) {
          if (!tokens.length) {
            continue;
          }

          const nowLocal = toOffsetDate(nowUtc, offsetMinutes);

          if (wasTakenToday(medication.lastTaken, nowLocal, offsetMinutes)) {
            continue;
          }

          const dueLocal = new Date(
            Date.UTC(
              nowLocal.getUTCFullYear(),
              nowLocal.getUTCMonth(),
              nowLocal.getUTCDate(),
              parsedTime.hour,
              parsedTime.minute,
              0,
              0
            )
          );
          dueLocal.setUTCMinutes(
            dueLocal.getUTCMinutes() - reminderOffsetMinutes
          );

          if (!isSameUtcMinute(dueLocal, nowLocal)) {
            continue;
          }

          const dispatchKey = buildDispatchKey({
            userId,
            medicationId,
            offsetMinutes,
            dueLocal,
            reminderOffsetMinutes,
          });

          const created = await tryCreateDispatchLock(dispatchKey);
          if (!created) {
            dispatchesSkipped += 1;
            continue;
          }

          const title = "Medication Reminder";
          const response = await sendMulticast(tokens, {
            notification: {
              title,
              body: reminderBody,
            },
            data: {
              medicationId,
              userId,
              dueAtLocalMinute: formatUtcMinute(dueLocal),
              reminderInterval,
            },
          });

          remindersSent += response.successCount;
        }
      }
    }

    logger.info("Medication reminder dispatch completed", {
      usersScanned,
      remindersSent,
      dispatchesSkipped,
      ranAtUtc: nowUtc.toISOString(),
    });
  }
);

function normalizeReminderInterval(interval) {
  const value = typeof interval === "string" ? interval.trim() : "";
  if (!value) {
    return DEFAULT_REMINDER_INTERVAL;
  }
  const supported = new Set([
    "At exact time",
    "5 minutes before",
    "10 minutes before",
    "15 minutes before",
    "30 minutes before",
  ]);
  return supported.has(value) ? value : DEFAULT_REMINDER_INTERVAL;
}

function reminderOffsetMinutesFromInterval(interval) {
  const normalized = normalizeReminderInterval(interval);
  if (normalized === "At exact time") {
    return 0;
  }

  const match = normalized.match(/^(\d+)\s+minutes?\s+before$/i);
  if (!match) {
    return 0;
  }

  const minutes = Number.parseInt(match[1], 10);
  return Number.isFinite(minutes) && minutes > 0 ? minutes : 0;
}

function parseMedicationTime(timeValue) {
  if (typeof timeValue !== "string") {
    return null;
  }

  const value = timeValue.trim();

  const amPmMatch = value.match(/^(\d{1,2}):(\d{2})\s*([AaPp][Mm])$/);
  if (amPmMatch) {
    let hour = Number.parseInt(amPmMatch[1], 10);
    const minute = Number.parseInt(amPmMatch[2], 10);
    const period = amPmMatch[3].toUpperCase();

    if (!Number.isFinite(hour) || !Number.isFinite(minute)) {
      return null;
    }

    if (period === "PM" && hour < 12) {
      hour += 12;
    }
    if (period === "AM" && hour === 12) {
      hour = 0;
    }

    return {
      hour: clamp(hour, 0, 23),
      minute: clamp(minute, 0, 59),
    };
  }

  const twentyFourMatch = value.match(/^(\d{1,2}):(\d{2})$/);
  if (twentyFourMatch) {
    const hour = Number.parseInt(twentyFourMatch[1], 10);
    const minute = Number.parseInt(twentyFourMatch[2], 10);

    if (!Number.isFinite(hour) || !Number.isFinite(minute)) {
      return null;
    }

    return {
      hour: clamp(hour, 0, 23),
      minute: clamp(minute, 0, 59),
    };
  }

  return null;
}

function groupTokensByOffset(tokenDocs) {
  const groups = new Map();

  for (const tokenDoc of tokenDocs) {
    const data = tokenDoc.data() || {};
    const token = typeof data.token === "string" ? data.token.trim() : "";
    if (!token) {
      continue;
    }

    const offsetMinutes = Number.isFinite(data.timezoneOffsetMinutes)
      ? data.timezoneOffsetMinutes
      : 0;

    const existing = groups.get(offsetMinutes) || [];
    existing.push(token);
    groups.set(offsetMinutes, existing);
  }

  return groups;
}

function isMedicationEligible(medication) {
  if (!medication || typeof medication !== "object") {
    return false;
  }
  if (medication.isActive === false) {
    return false;
  }
  if (medication.notificationsEnabled === false) {
    return false;
  }
  if (typeof medication.time !== "string" || !medication.time.trim()) {
    return false;
  }
  return true;
}

function toOffsetDate(utcDate, offsetMinutes) {
  return new Date(utcDate.getTime() + offsetMinutes * 60 * 1000);
}

function wasTakenToday(lastTakenValue, nowLocal, offsetMinutes) {
  const takenDateUtc = parseUnknownDate(lastTakenValue);
  if (!takenDateUtc) {
    return false;
  }

  const takenLocal = toOffsetDate(takenDateUtc, offsetMinutes);
  return (
    takenLocal.getUTCFullYear() === nowLocal.getUTCFullYear() &&
    takenLocal.getUTCMonth() === nowLocal.getUTCMonth() &&
    takenLocal.getUTCDate() === nowLocal.getUTCDate()
  );
}

function parseUnknownDate(value) {
  if (!value) {
    return null;
  }

  if (typeof value.toDate === "function") {
    return value.toDate();
  }

  if (value instanceof Date) {
    return value;
  }

  if (typeof value === "string") {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }

  if (typeof value === "number") {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }

  return null;
}

function isSameUtcMinute(a, b) {
  return (
    a.getUTCFullYear() === b.getUTCFullYear() &&
    a.getUTCMonth() === b.getUTCMonth() &&
    a.getUTCDate() === b.getUTCDate() &&
    a.getUTCHours() === b.getUTCHours() &&
    a.getUTCMinutes() === b.getUTCMinutes()
  );
}

function buildDispatchKey({
  userId,
  medicationId,
  offsetMinutes,
  dueLocal,
  reminderOffsetMinutes,
}) {
  return [
    userId,
    medicationId,
    offsetMinutes,
    reminderOffsetMinutes,
    formatUtcMinute(dueLocal),
  ].join("_");
}

function formatUtcMinute(date) {
  const year = date.getUTCFullYear();
  const month = String(date.getUTCMonth() + 1).padStart(2, "0");
  const day = String(date.getUTCDate()).padStart(2, "0");
  const hour = String(date.getUTCHours()).padStart(2, "0");
  const minute = String(date.getUTCMinutes()).padStart(2, "0");
  return `${year}${month}${day}${hour}${minute}`;
}

async function tryCreateDispatchLock(dispatchKey) {
  try {
    await db.collection(DISPATCH_COLLECTION).doc(dispatchKey).create({
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return true;
  } catch (error) {
    if (error && error.code === 6) {
      return false;
    }

    logger.warn("Dispatch lock create failed", {
      dispatchKey,
      error: String(error),
    });
    return false;
  }
}

async function sendMulticast(tokens, payload) {
  const chunkSize = 500;
  let successCount = 0;
  let failureCount = 0;

  for (let index = 0; index < tokens.length; index += chunkSize) {
    const chunk = tokens.slice(index, index + chunkSize);
    const response = await admin.messaging().sendEachForMulticast({
      tokens: chunk,
      ...payload,
    });

    successCount += response.successCount;
    failureCount += response.failureCount;
  }

  return {successCount, failureCount};
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value));
}
