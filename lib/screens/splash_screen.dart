import 'dart:async';

import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {

  double progress = 0;

  @override
  void initState() {
    super.initState();

    Timer.periodic(const Duration(milliseconds: 2), (timer) {
      setState(() {
        progress += 0.01;
      });

      if (progress >= 1) {
        timer.cancel();

        Navigator.pushReplacementNamed(context, "/login");
      }
    });
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: Colors.black,

      body: Stack(

        children: [

          /// Background Image

          Positioned.fill(
            child: Opacity(
              opacity: .28,
              child: Image.asset(
                "assets/images/splash_bg.png",
                fit: BoxFit.cover,
              ),
            ),
          ),

          /// Black Gradient

          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [

                    Colors.black,

                    Colors.black87,

                    Colors.black,

                  ],
                ),
              ),
            ),
          ),

          /// Content

          SafeArea(
            child: Column(

              children: [

                const Spacer(),

                Image.asset(
                  "assets/img/vitrax_logo.png",
                  width: 170,
                ),

                const Spacer(),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 35),

                  child: Column(

                    children: [

                      ClipRRect(

                        borderRadius: BorderRadius.circular(20),

                        child: LinearProgressIndicator(

                          value: progress,

                          minHeight: 4,

                          backgroundColor: Colors.grey.shade800,

                          valueColor:
                              const AlwaysStoppedAnimation(
                            Color(0xff1565FF),
                          ),
                        ),
                      ),

                      const SizedBox(height: 15),

                      const Text(

                        "Loading your experience...",

                        style: TextStyle(

                          color: Colors.grey,

                          fontSize: 13,

                        ),
                      ),

                      const SizedBox(height: 25),

                    ],
                  ),
                )

              ],
            ),
          ),

        ],
      ),
    );
  }
}