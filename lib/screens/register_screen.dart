import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'loading_screen.dart';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final supabase = Supabase.instance.client;
  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  bool isLoading = false;

  int selectedActivity = -1; // 0 = Cyclist, 1 = Runner

  String? firstNameError;
  String? lastNameError;
  String? emailError;
  String? passwordError;
  String? confirmPasswordError;
  bool isConnected = true;

  late final StreamSubscription<List<ConnectivityResult>>
  _connectionSubscription;

  Future<void> checkInternet() async {
    final connected = await InternetConnection().hasInternetAccess;

    if (!mounted) return;

    setState(() {
      isConnected = connected;
    });
  }

  Widget buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    String? errorText,
    TextInputType keyboardType = TextInputType.text,
    bool obscure = false,
    bool showEye = false,
    VoidCallback? onEyeTap,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      onChanged: onChanged,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        errorText: errorText,
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.grey),
        prefixIcon: Icon(icon, color: Colors.grey),
        suffixIcon: showEye
            ? IconButton(
                icon: Icon(
                  obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: Colors.grey,
                ),
                onPressed: onEyeTap,
              )
            : null,
        filled: true,
        fillColor: const Color(0xff111111),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade800),
        ),

        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xff3D7DFF), width: 2),
        ),

        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.red),
        ),

        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
      ),
    );
  }

  Widget activityCard({
    required int index,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    bool selected = selectedActivity == index;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            selectedActivity = index;
          });
        },
        child: Container(
          padding: const EdgeInsets.all(15),
          constraints: const BoxConstraints(minHeight: 170),
          decoration: BoxDecoration(
            color: const Color(0xff111111),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? const Color(0xff3D7DFF) : Colors.grey.shade800,
              width: selected ? 2 : 1,
            ),
          ),
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: CircleAvatar(
                  radius: 10,
                  backgroundColor: selected
                      ? const Color(0xff3D7DFF)
                      : Colors.transparent,
                  child: selected
                      ? const Icon(Icons.check, color: Colors.white, size: 14)
                      : Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.grey),
                          ),
                        ),
                ),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: const Color(0xff3D7DFF), size: 38),
                  const SizedBox(height: 10),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white70,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Future<void> registerUser() async {
    setState(() {
      firstNameError = null;
      lastNameError = null;
      emailError = null;
      passwordError = null;
      confirmPasswordError = null;
    });

    bool valid = true;
    final firstName = firstNameController.text.trim();
    final password = passwordController.text;

    if (firstName.isEmpty) {
      firstNameError = "First name is required.";
      valid = false;
    } else if (!RegExp(r'^[A-Za-z ]+$').hasMatch(firstName)) {
      firstNameError = "First name must contain only letters.";
      valid = false;
    }

    if (lastNameController.text.trim().isEmpty) {
      lastNameError = "Last name is required.";
      valid = false;
    }

    if (emailController.text.trim().isEmpty) {
      emailError = "Email is required.";
      valid = false;
    } else if (!RegExp(
      r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
    ).hasMatch(emailController.text.trim())) {
      emailError = "Please enter a valid email.";
      valid = false;
    }

    if (password.isEmpty) {
      passwordError = "Password is required.";
      valid = false;
    } else if (password.length < 8) {
      passwordError = "Password must be at least 8 characters.";
      valid = false;
    } else if (!RegExp(r'[A-Z]').hasMatch(password)) {
      passwordError = "Password must contain at least one uppercase letter.";
      valid = false;
    } else if (!RegExp(r'[a-z]').hasMatch(password)) {
      passwordError = "Password must contain at least one lowercase letter.";
      valid = false;
    } else if (!RegExp(r'[0-9]').hasMatch(password)) {
      passwordError = "Password must contain at least one number.";
      valid = false;
    } else if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(password)) {
      passwordError = "Password must contain at least one special character.";
      valid = false;
    }

    if (confirmPasswordController.text != passwordController.text) {
      confirmPasswordError = "Passwords do not match.";
      valid = false;
    }
    if (selectedActivity == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select your activity.")),
      );
      return;
    }

    if (!valid) {
      setState(() {});
      return;
    }

    setState(() => isLoading = true);
    await checkInternet();

    if (!isConnected) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No internet connection. Please check your network."),
          behavior: SnackBarBehavior.floating,
        ),
      );

      setState(() {
        isLoading = false;
      });

      return;
    }

    try {
      final response = await supabase.auth.signUp(
        email: emailController.text.trim(),
        password: passwordController.text,
        data: {
          'first_name': firstNameController.text.trim(),
          'last_name': lastNameController.text.trim(),
          'primary_activity': selectedActivity == 0 ? 'Cyclist' : 'Runner',
        },
      );

      final user = response.user;

      // Email confirmation is OFF in the Supabase project right now, so a
      // successful sign-up already comes back signed in (it has a
      // session): go straight into the app like a normal login. If
      // confirmation is ever turned back on, session is null and the
      // "Check your email" dialog below shows instead.
      if (user != null && response.session != null) {
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoadingScreen()),
          (route) => false,
        );
        return;
      }

      if (user != null) {
        // The `profiles` row itself is created automatically by a
        // database trigger (see supabase/012_auto_create_profile.sql)
        // that reads the metadata passed above. It is NOT inserted here
        // on the client: signUp() does not hand this client an
        // authenticated session while email confirmation is required,
        // so an insert attempted at this point runs unauthenticated and
        // gets rejected by the profiles table's row-level security
        // policy (error 42501).
        if (mounted) {
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => AlertDialog(
              backgroundColor: const Color(0xff111111),
              title: const Text('Check your email', style: TextStyle(color: Colors.white)),
              content: Text(
                "We've sent a confirmation link to ${emailController.text.trim()}. Open it to verify the address is real before you can sign in.",
                style: const TextStyle(color: Colors.grey),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    try {
                      await supabase.auth.resend(type: OtpType.signup, email: emailController.text.trim());
                      if (dialogContext.mounted) {
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(content: Text('Confirmation email resent.')),
                        );
                      }
                    } catch (_) {}
                  },
                  child: const Text('Resend Email', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xff3D7DFF)),
                  child: const Text('Got it', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );

          if (mounted) Navigator.pop(context);
        }
      }
    } on AuthException catch (e) {
      setState(() {
        final message = e.message.toLowerCase();

        if (message.contains("already") ||
            message.contains("registered") ||
            message.contains("exists")) {
          emailError = "This email is already registered.";
        } else if (message.contains("invalid email")) {
          emailError = "Please enter a valid email address.";
        } else if (message.contains("password")) {
          passwordError = e.message;
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.message)));
        }
      });
    } catch (e, stackTrace) {
      debugPrint("REGISTER ERROR:");
      debugPrint(e.toString());
      debugPrint(stackTrace.toString());

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Unable to connect to the server. Please try again later.",
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    if (mounted) {
      setState(() {
        isLoading = false;
      });
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

  @override
  void dispose() {
    _connectionSubscription.cancel();

    firstNameController.dispose();
    lastNameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),

              const SizedBox(height: 10),

              Center(
                child: Image.asset("assets/img/vitrax_logo.png", height: 95),
              ),

              const SizedBox(height: 30),

              const Text(
                "Create your account",
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                "Join VitraX and start your journey today",
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),

              const SizedBox(height: 35),
              const SizedBox(height: 25),

              if (!isConnected)
                Container(
                  margin: const EdgeInsets.only(bottom: 25),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.wifi_off, color: Colors.orange),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "You're offline. Please connect to the internet to create an account.",
                          style: TextStyle(color: Colors.orange),
                        ),
                      ),
                    ],
                  ),
                ),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        sectionTitle("FIRST NAME"),
                        buildTextField(
                          controller: firstNameController,
                          hint: "First name",
                          icon: Icons.person_outline,
                          errorText: firstNameError,
                          onChanged: (_) {
                            if (firstNameError != null) {
                              setState(() {
                                firstNameError = null;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        sectionTitle("LAST NAME"),
                        buildTextField(
                          controller: lastNameController,
                          hint: "Last name",
                          icon: Icons.person_outline,
                          errorText: lastNameError,
                          onChanged: (_) {
                            if (lastNameError != null) {
                              setState(() {
                                lastNameError = null;
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              sectionTitle("EMAIL"),

              buildTextField(
                controller: emailController,
                hint: "Your email address",
                icon: Icons.email_outlined,
                errorText: emailError,
                onChanged: (_) {
                  if (emailError != null) {
                    setState(() {
                      emailError = null;
                    });
                  }
                },
              ),

              const SizedBox(height: 20),

              sectionTitle("PASSWORD"),

              buildTextField(
                controller: passwordController,
                hint: "Create a password",
                icon: Icons.lock_outline,
                obscure: _obscurePassword,
                errorText: passwordError,
                showEye: true,
                onEyeTap: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
                onChanged: (_) {
                  if (passwordError != null) {
                    setState(() {
                      passwordError = null;
                    });
                  }
                },
              ),

              const SizedBox(height: 20),

              sectionTitle("CONFIRM PASSWORD"),

              buildTextField(
                controller: confirmPasswordController,
                hint: "Confirm your password",
                icon: Icons.lock_outline,
                obscure: _obscureConfirmPassword,
                errorText: confirmPasswordError,
                showEye: true,
                onEyeTap: () {
                  setState(() {
                    _obscureConfirmPassword = !_obscureConfirmPassword;
                  });
                },
                onChanged: (_) {
                  if (confirmPasswordError != null) {
                    setState(() {
                      confirmPasswordError = null;
                    });
                  }
                },
              ),

              const SizedBox(height: 28),

              const Text(
                "PRIMARY ACTIVITY",
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 5),

              const Text(
                "Choose your main activity to personalize your experience.",
                style: TextStyle(color: Colors.grey),
              ),

              const SizedBox(height: 18),

              Row(
                children: [
                  activityCard(
                    index: 0,
                    icon: Icons.directions_bike,
                    title: "Cyclist",
                    subtitle: "Join cycling events,\ntrack rides and connect.",
                  ),
                  const SizedBox(width: 15),
                  activityCard(
                    index: 1,
                    icon: Icons.directions_run,
                    title: "Runner",
                    subtitle: "Join running events,\ntrack runs and connect.",
                  ),
                ],
              ),

              const SizedBox(height: 35),

              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xff3D7DFF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  onPressed: isLoading ? null : registerUser,
                  child: isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "Create Account",
                          style: TextStyle(
                            fontSize: 20,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 35),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Already have an account?",
                    style: TextStyle(color: Colors.grey),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text(
                      "Sign In",
                      style: TextStyle(
                        color: Color(0xFF3D7DFF),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
