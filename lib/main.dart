import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  // 1. Ensure Flutter framework bindings are ready
  WidgetsFlutterBinding.ensureInitialized();
  
  print("🚀 [TEST] Initializing Firebase native channels...");
  try {
    // 2. Initialize connection payload via google-services.json
    await Firebase.initializeApp();
    print("✅ [TEST] Firebase Core initialized successfully!");

    print("🛰️ [TEST] Attempting cloud pipeline handshake with Firestore...");
    // 3. Write a temporary validation flag to your Firestore instance
    await FirebaseFirestore.instance.collection('connection_test').add({
      'status': 'Connected Successfully!',
      'timestamp': FieldValue.serverTimestamp(),
    });
    
    print("🎉 [SUCCESS] Data successfully pushed to the cloud! Your app is perfectly linked to Firebase.");
  } catch (e) {
    print("❌ [FAILURE] Connection test failed with error: $e");
    print("👉 Check if your google-services.json file is inside android/app/ or update your Firestore cloud rules.");
  }

  // Fallback simple UI placeholder so the build compiles completely
  runApp(const MaterialApp(
    home: Scaffold(
      body: Center(child: Text("Check your VS Code Debug Console log outputs.")),
    ),
  ));
}
