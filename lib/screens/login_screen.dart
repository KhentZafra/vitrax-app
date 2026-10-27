import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'loading_screen.dart';
import 'forgot_password_screen.dart';
import '../widgets/email_code_dialog.dart';
import '../widgets/auth_decor.dart';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final supabase = Supabase.instance.client;

  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isConnected = true;
  late final StreamSubscription<List<ConnectivityResult>>
  _connectionSubscription;
  bool hidePassword = true;
  bool isLoading = false;
  final _formKey = GlobalKey<FormState>();

  String? emailError;
  String? passwordError;

  Future<void> checkInternet() async {
    final connected = await InternetConnection().hasInternetAccess;

    if (!mounted) return;

    setState(() {
      isConnected = connected;
    });
  }

  Future<void> _resendConfirmationEmail() async {
    try {
      final email = emailController.text.trim();
      await supabase.auth.resend(type: OtpType.signup, email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).clearSnackBars();
      final ok = await showEmailCodeDialog(
        context,
        email: email,
        type: OtpType.signup,
        title: 'Verify your email',
        message: 'We sent a 6-digit code to $email. Enter it to confirm your account.',
      );
      if (ok && mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoadingScreen()));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't resend the email. Try again shortly."),
        ),
      );
    }
  }

  Future<void> signIn() async {
    emailError = null;
    passwordError = null;

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      isLoading = true;
    });
    await checkInternet();

    if (!isConnected) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No Internet connection, Please connect it to the internet"),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );

      setState(() {
        isLoading = false;
      });

      return;
    }

    try {
      await supabase.auth.signInWithPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoadingScreen()),
      );
    } on AuthException catch (e) {
      setState(() {
        final message = e.message.toLowerCase();

        if (message.contains("invalid login credentials")) {
          passwordError = "Incorrect email or password.";
        } else if (message.contains("invalid email")) {
          emailError = "Please enter a valid email address.";
        } else if (message.contains("not confirmed")) {
          emailError = "Please confirm your email first, check your inbox.";
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text("Your email isn't confirmed yet."),
              action: SnackBarAction(
                label: 'Resend',
                onPressed: _resendConfirmationEmail,
              ),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } else {
          passwordError = e.message;
        }
      });
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Unable to connect to the server. Please try again later.",
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();

    checkInternet();

    _connectionSubscription = Connectivity().onConnectivityChanged.listen((_) {
      checkInternet();
    });
  }

  static const _blue = Color(0xff0a77ff);

  InputDecoration _fieldDecoration({required String hint, required IconData icon, String? errorText, Widget? suffix}) {
    OutlineInputBorder border(Color c, [double w = 1]) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide(color: c, width: w));
    return InputDecoration(
      hintText: hint,
      errorText: errorText,
      hintStyle: const TextStyle(color: Color(0xff8e9099), fontSize: 16),
      prefixIcon: Icon(icon, color: Colors.white70, size: 26),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xff070b14),
      contentPadding: const EdgeInsets.symmetric(vertical: 18),
      enabledBorder: border(const Color(0xff1c5fe0)),
      focusedBorder: border(_blue, 1.6),
      errorBorder: border(Colors.red),
      focusedErrorBorder: border(Colors.red, 2),
    );
  }

  Widget _glow(Widget child) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: _blue.withValues(alpha: 0.18), blurRadius: 16)],
        ),
        child: child,
      );

  Widget _fadeEdge({required Widget child, required bool fadeBottom}) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: fadeBottom ? const [Colors.white, Colors.white, Colors.transparent] : const [Colors.transparent, Colors.white, Colors.white],
        stops: fadeBottom ? const [0, 0.78, 1] : const [0, 0.25, 1],
      ).createShader(rect),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, cons) {
          final w = cons.maxWidth;
          final h = cons.maxHeight;
          // The form needs about this much height; whatever is left over
          // goes to the runner picture, so the page never needs scrolling.
          const formHeight = 548.0;
          final heroH = keyboardOpen ? 0.0 : (h - formHeight - bottomInset).clamp(0.0, w * 640 / 840).toDouble();
          return Stack(
            children: [
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: _fadeEdge(fadeBottom: false, child: Image.asset('assets/img/login_bottom.jpg', width: w, fit: BoxFit.fitWidth)),
                ),
              ),
              Column(
                children: [
                  SizedBox(
                    height: heroH,
                    width: w,
                    child: heroH <= 0
                        ? null
                        : IgnorePointer(
                            child: _fadeEdge(
                              fadeBottom: true,
                              child: Image.asset('assets/img/login_hero.jpg', width: w, height: heroH, fit: BoxFit.cover, alignment: Alignment.center),
                            ),
                          ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(30, 0, 30, 12 + bottomInset),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.topCenter,
                        child: SizedBox(width: w - 60, child: _buildForm()),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('WELCOME BACK', style: techText(12, weight: 400, letterSpacing: 6, color: Colors.white70)),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: RichText(
              text: TextSpan(
                style: techText(28, weight: 800, italic: true),
                children: const [
                  TextSpan(text: 'Good to '),
                  TextSpan(text: 'see you', style: TextStyle(color: _blue)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text('Sign in to continue your journey', style: authBodyStyle),
          const SizedBox(height: 24),
          if (!isConnected)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red),
              ),
              child: const Row(
                children: [
                  Icon(Icons.wifi_off, color: Colors.red),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text("No Internet connection, Please connect it to the internet", style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ),
          Text('EMAIL', style: authLabelStyle),
          const SizedBox(height: 10),
          _glow(
            TextFormField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) {
                if (emailError != null) setState(() => emailError = null);
              },
              style: const TextStyle(color: Colors.white, fontSize: 16),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return "Email is required.";
                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value.trim())) return "Please enter a valid email.";
                return null;
              },
              decoration: _fieldDecoration(hint: 'your@email.com', icon: Icons.mail_outline, errorText: emailError),
            ),
          ),
          const SizedBox(height: 20),
          Text('PASSWORD', style: authLabelStyle),
          const SizedBox(height: 10),
          _glow(
            TextFormField(
              controller: passwordController,
              obscureText: hidePassword,
              onChanged: (_) {
                if (passwordError != null) setState(() => passwordError = null);
              },
              style: const TextStyle(color: Colors.white, fontSize: 16),
              validator: (value) {
                if (value == null || value.isEmpty) return "Password is required.";
                if (value.length < 8) return "Password must be at least 8 characters.";
                return null;
              },
              decoration: _fieldDecoration(
                hint: '••••••••',
                icon: Icons.lock_outline,
                errorText: passwordError,
                suffix: IconButton(
                  icon: Icon(hidePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: Colors.white70),
                  onPressed: () => setState(() => hidePassword = !hidePassword),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ForgotPasswordScreen(initialEmail: emailController.text.trim()))),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Forgot password?', style: authLinkStyle),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward, color: _blue, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          GlowButton(label: 'SIGN IN', spaced: true, loading: isLoading, height: 58, onPressed: isLoading ? null : signIn),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("Don't have an account?", style: authBodyStyle),
              TextButton(
                onPressed: () => Navigator.pushNamed(context, '/register'),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Register', style: authLinkStyle),
                    SizedBox(width: 6),
                    Icon(Icons.arrow_forward, color: _blue, size: 18),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _connectionSubscription.cancel();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }
}
