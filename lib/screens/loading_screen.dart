import 'package:flutter/material.dart';
import 'package:skeletonizer/skeletonizer.dart';

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

    Navigator.pushReplacementNamed(
      context,
      "/activitySelection",
    );
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