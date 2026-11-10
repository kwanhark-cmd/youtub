import 'package:flutter/material.dart';

import 'src/clean_screen.dart';
import 'src/doc_screen.dart';
import 'src/edit_screen.dart';
import 'src/stamp_screen.dart';

void main() => runApp(const MetaCleanApp());

class MetaCleanApp extends StatelessWidget {
  const MetaCleanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '메타지우개 플러스',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F6BFF)),
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
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('메타지우개 플러스'),
          bottom: const TabBar(
            labelPadding: EdgeInsets.symmetric(horizontal: 4),
            tabs: [
              Tab(icon: Icon(Icons.cleaning_services), text: '사진 지우기'),
              Tab(icon: Icon(Icons.edit_location_alt), text: '사진 수정'),
              Tab(icon: Icon(Icons.description), text: '문서'),
              Tab(icon: Icon(Icons.edit_calendar), text: '구매 기록'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [CleanScreen(), EditScreen(), DocScreen(), StampScreen()],
        ),
      ),
    );
  }
}
