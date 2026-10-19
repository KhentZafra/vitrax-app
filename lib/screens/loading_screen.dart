import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'legal_screen.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {

  @override
  void initState() {
    super.initState();

    loadApp();
  }

  Future<void> loadApp() async {
    // TODO:
    // Load profile
    // Load events
    // Load community feed
    // Check internet

    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    // An admin can suspend an account from the admin website. A suspended
    // user is signed straight back out instead of entering the app.
    if (await _isSuspended()) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);
      await Supabase.instance.client.auth.signOut();
      navigator.pushNamedAndRemoveUntil('/login', (route) => false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Your account has been suspended. Contact the VITRAX team for help.')),
      );
      return;
    }

    // Accounts made before the Privacy Policy existed (or when it changes)
    // must accept it once. Declining signs them out.
    if (!await ConsentGate.hasAccepted()) {
      if (!mounted) return;
      final accepted = await ConsentGate.prompt(context);
      if (!accepted) {
        await Supabase.instance.client.auth.signOut();
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
        return;
      }
    }

    if (!mounted) return;
    Navigator.pushReplacementNamed(
      context,
      "/activitySelection",
    );
  }

  Future<bool> _isSuspended() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return false;
    try {
      final row = await Supabase.instance.client.from('profiles').select('is_suspended').eq('id', user.id).maybeSingle();
      return row?['is_suspended'] == true;
    } catch (_) {
      // Column not added yet (018_admin.sql not run) or offline: let the user in.
      return false;
    }
  }

  Widget skeletonCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [

          Row(
            children: [

              const CircleAvatar(radius: 25),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [

                    Text(
                      "Loading User",
                      style: TextStyle(color: Colors.white),
                    ),

                    SizedBox(height: 8),

                    Text(
                      "Loading Time",
                      style: TextStyle(color: Colors.white),
                    ),

                  ],
                ),
              ),

            ],
          ),

          const SizedBox(height: 18),

          Container(
            height: 18,
            width: double.infinity,
            color: Colors.white,
          ),

          const SizedBox(height: 10),

          Container(
            height: 18,
            width: double.infinity,
            color: Colors.white,
          ),

          const SizedBox(height: 10),

          Container(
            height: 18,
            width: 220,
            color: Colors.white,
          ),

          const SizedBox(height: 20),

          Container(
            height: 170,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
            ),
          ),

          const SizedBox(height: 18),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [

              Container(
                width: 70,
                height: 16,
                color: Colors.white,
              ),

              Container(
                width: 70,
                height: 16,
                color: Colors.white,
              ),

              Container(
                width: 70,
                height: 16,
                color: Colors.white,
              ),

            ],
          ),

        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Skeletonizer(
          enabled: true,
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [

              Row(
                children: [

                  const CircleAvatar(radius: 28),

                  const SizedBox(width: 15),

                  Expanded(
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  Container(
                    width: 45,
                    height: 45,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),

                ],
              ),

              const SizedBox(height: 30),

              skeletonCard(),

              skeletonCard(),

              skeletonCard(),

            ],
          ),
        ),
      ),
    );
  }
}