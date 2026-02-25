import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();

  FirebaseService._internal();

  factory FirebaseService() {
    return _instance;
  }

  // Firebase instances
  FirebaseAuth get auth => FirebaseAuth.instance;
  FirebaseFirestore get firestore => FirebaseFirestore.instance;
  FirebaseStorage get storage => FirebaseStorage.instance;

  String _requireUserId() {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError('No authenticated user');
    }
    return user.uid;
  }

  // Authentication methods
  Future<UserCredential?> signUp(String email, String password) async {
    try {
      return await auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      print('Sign up error: $e');
      return null;
    }
  }

  Future<UserCredential?> signIn(String email, String password) async {
    try {
      return await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      print('Sign in error: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      await auth.signOut();
    } catch (e) {
      print('Sign out error: $e');
    }
  }

  User? getCurrentUser() {
    return auth.currentUser;
  }

  // Firestore methods
  Future<void> addDocument(String collection, Map<String, dynamic> data) async {
    try {
      await firestore.collection(collection).add(data);
    } catch (e) {
      print('Add document error: $e');
    }
  }

  // User-scoped Firestore methods
  Future<void> addUserDocument(
    String collection,
    Map<String, dynamic> data,
  ) async {
    try {
      final userId = _requireUserId();
      await firestore
          .collection('users')
          .doc(userId)
          .collection(collection)
          .add(data);
    } catch (e) {
      print('Add user document error: $e');
      rethrow;
    }
  }

  Future<QuerySnapshot> getUserDocuments(String collection) async {
    try {
      final userId = _requireUserId();
      return await firestore
          .collection('users')
          .doc(userId)
          .collection(collection)
          .get();
    } catch (e) {
      print('Get user documents error: $e');
      rethrow;
    }
  }

  Stream<QuerySnapshot> streamUserDocuments(String collection) {
    final userId = _requireUserId();
    return firestore
        .collection('users')
        .doc(userId)
        .collection(collection)
        .snapshots();
  }

  Future<void> updateUserDocument(
    String collection,
    String docId,
    Map<String, dynamic> data,
  ) async {
    try {
      final userId = _requireUserId();
      await firestore
          .collection('users')
          .doc(userId)
          .collection(collection)
          .doc(docId)
          .update(data);
    } catch (e) {
      print('Update user document error: $e');
      rethrow;
    }
  }

  Future<void> deleteUserDocument(String collection, String docId) async {
    try {
      final userId = _requireUserId();
      await firestore
          .collection('users')
          .doc(userId)
          .collection(collection)
          .doc(docId)
          .delete();
    } catch (e) {
      print('Delete user document error: $e');
      rethrow;
    }
  }

  Future<QuerySnapshot> getDocuments(String collection) async {
    try {
      return await firestore.collection(collection).get();
    } catch (e) {
      print('Get documents error: $e');
      rethrow;
    }
  }

  Stream<QuerySnapshot> streamDocuments(String collection) {
    return firestore.collection(collection).snapshots();
  }

  Future<void> updateDocument(
    String collection,
    String docId,
    Map<String, dynamic> data,
  ) async {
    try {
      await firestore.collection(collection).doc(docId).update(data);
    } catch (e) {
      print('Update document error: $e');
      rethrow;
    }
  }

  Future<void> deleteDocument(String collection, String docId) async {
    try {
      await firestore.collection(collection).doc(docId).delete();
    } catch (e) {
      print('Delete document error: $e');
      rethrow;
    }
  }

  // Storage methods
  Future<String> uploadFile(String path, String fileName) async {
    try {
      final file = File(path);
      await storage.ref('uploads/$fileName').putFile(file);
      return await storage.ref('uploads/$fileName').getDownloadURL();
    } catch (e) {
      print('Upload file error: $e');
      rethrow;
    }
  }

  Future<String> getDownloadURL(String filePath) async {
    try {
      return await storage.ref(filePath).getDownloadURL();
    } catch (e) {
      print('Get download URL error: $e');
      rethrow;
    }
  }
}
