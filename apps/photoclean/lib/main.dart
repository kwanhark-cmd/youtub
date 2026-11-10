import 'package:flutter/material.dart';

import 'src/clean_screen.dart';
import 'src/stamp_screen.dart';

void main() => runApp(const PhotoCleanApp());

class PhotoCleanApp extends StatelessWidget {
  const PhotoCleanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '사진 메타지우개',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1FA48A)),
        useMaterial3: true,
      ),
      home: const _Home(),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('사진 메타지우개'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.cleaning_services), text: '지우기 (판매)'),
              Tab(icon: Icon(Icons.edit_calendar), text: '기록 (구매)'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [CleanScreen(), StampScreen()],
        ),
      ),
    );
  }
}
