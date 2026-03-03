import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/app_theme.dart';
import '../services/firebase_service.dart';
import '../services/push_notification_service.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _nameFocusNode = FocusNode();

  final FirebaseService _firebaseService = FirebaseService();
  final PushNotificationService _pushNotificationService =
      PushNotificationService();

  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _hoveredField;

  @override
  void initState() {
    super.initState();
    _nameFocusNode.addListener(_onFocusChange);
    _emailFocusNode.addListener(_onFocusChange);
    _passwordFocusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();

    _nameFocusNode.removeListener(_onFocusChange);
    _emailFocusNode.removeListener(_onFocusChange);
    _passwordFocusNode.removeListener(_onFocusChange);

    _nameFocusNode.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _isLoading) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text.trim();

      if (_isLogin) {
        await _firebaseService.signIn(email, password);
      } else {
        await _firebaseService.signUp(
          email,
          password,
          name: _nameController.text.trim(),
        );
      }

      await _pushNotificationService.syncTokenForCurrentUser();

      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/home');
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      final message =
          error.message ?? 'Authentication failed. Please try again.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _sendResetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter your email first to reset password.'),
        ),
      );
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset email sent.')),
      );
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? 'Failed to send reset email.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.veryLightGreen,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_isLogin) ...[
                        Align(
                          alignment: Alignment.center,
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: AppColors.lightGreen,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.favorite_rounded,
                              color: AppColors.darkGreen,
                              size: 28,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      Text(
                        _isLogin ? 'Welcome' : 'Create Account',
                        style: const TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkText,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        _isLogin
                            ? 'Sign in to continue your medication journey.'
                            : 'Join us and start your journey today.',
                        style: const TextStyle(
                          fontSize: 16,
                          color: AppColors.lightText,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (!_isLogin) ...[
                        _buildAnimatedInputField(
                          fieldKey: 'name',
                          controller: _nameController,
                          focusNode: _nameFocusNode,
                          hintText: 'Your Name',
                          prefixIcon: Icons.person_outline_rounded,
                          textInputAction: TextInputAction.next,
                          validator: (value) {
                            final name = value?.trim() ?? '';
                            if (name.isEmpty) {
                              return 'Please enter your name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      _buildAnimatedInputField(
                        fieldKey: 'email',
                        controller: _emailController,
                        focusNode: _emailFocusNode,
                        hintText: 'user@gmail.com',
                        prefixIcon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          if (email.isEmpty || !email.contains('@')) {
                            return 'Enter a valid email';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _buildAnimatedInputField(
                        fieldKey: 'password',
                        controller: _passwordController,
                        focusNode: _passwordFocusNode,
                        hintText: '••••••',
                        prefixIcon: Icons.lock_outline_rounded,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) {
                          _submit();
                        },
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: AppColors.lightText,
                          ),
                        ),
                        validator: (value) {
                          final password = value ?? '';
                          if (password.length < 6) {
                            return 'Password must be at least 6 characters';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (_isLogin)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _isLoading ? null : _sendResetPassword,
                            child: const Text(
                              'Forgot Password?',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      const SizedBox(height: AppSpacing.sm),
                      _AnimatedGradientButton(
                        label: _isLogin ? 'Login' : 'Sign Up',
                        loading: _isLoading,
                        onPressed: _isLoading ? null : _submit,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                                setState(() {
                                  _isLogin = !_isLogin;
                                });
                              },
                        child: Text(
                          _isLogin
                              ? "Don't have an account? Sign Up"
                              : 'Already have an account? Sign In',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppColors.darkGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedInputField({
    required String fieldKey,
    required TextEditingController controller,
    required FocusNode focusNode,
    required String hintText,
    required IconData prefixIcon,
    TextInputType? keyboardType,
    bool obscureText = false,
    TextInputAction? textInputAction,
    String? Function(String?)? validator,
    void Function(String)? onFieldSubmitted,
    Widget? suffixIcon,
  }) {
    final isFocused = focusNode.hasFocus;
    final isHovered = _hoveredField == fieldKey;
    final isActive = isFocused || isHovered;

    return MouseRegion(
      onEnter: (_) {
        if (!mounted) return;
        setState(() {
          _hoveredField = fieldKey;
        });
      },
      onExit: (_) {
        if (!mounted) return;
        if (_hoveredField == fieldKey) {
          setState(() {
            _hoveredField = null;
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isActive ? 0.11 : 0.06),
              blurRadius: isActive ? 12 : 7,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: TextFormField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: keyboardType,
          obscureText: obscureText,
          textInputAction: textInputAction,
          validator: validator,
          onFieldSubmitted: onFieldSubmitted,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: const TextStyle(
              color: AppColors.lightText,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
            prefixIcon: Icon(prefixIcon, color: AppColors.darkGreen),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              borderSide: const BorderSide(color: AppColors.borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              borderSide: BorderSide(
                color: isActive
                    ? AppColors.primaryGreen
                    : AppColors.borderColor,
                width: isActive ? 1.5 : 1,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              borderSide: const BorderSide(
                color: AppColors.primaryGreen,
                width: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedGradientButton extends StatefulWidget {
  const _AnimatedGradientButton({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final VoidCallback? onPressed;

  @override
  State<_AnimatedGradientButton> createState() =>
      _AnimatedGradientButtonState();
}

class _AnimatedGradientButtonState extends State<_AnimatedGradientButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: _pressed ? 0.98 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primaryGreen, AppColors.darkGreen],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onHighlightChanged: (value) {
                setState(() {
                  _pressed = value;
                });
              },
              onTap: widget.onPressed,
              child: Center(
                child: widget.loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        widget.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
