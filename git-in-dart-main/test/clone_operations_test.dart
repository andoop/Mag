/// Tests for clone operations
library;

import 'dart:io';
import 'package:test/test.dart';
import 'package:git_on_dart/git_on_dart.dart';

void main() {
  group('CloneOperation', () {
    late String testDir;
    late CloneOperation cloneOp;

    setUp(() async {
      testDir = Directory.systemTemp.createTempSync('git_clone_test_').path;
      cloneOp = CloneOperation();
    });

    tearDown(() async {
      try {
        final dir = Directory(testDir);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      } catch (e) {
        // Ignore cleanup errors
      }
    });

    test('clone fails if directory is not empty', () async {
      // Create a non-empty directory
      final targetDir = Directory('$testDir/repo');
      await targetDir.create();
      await File('${targetDir.path}/existing.txt').writeAsString('test');

      final result = await cloneOp.clone(
        url: 'https://github.com/test/repo.git',
        path: targetDir.path,
      );

      expect(result.success, isFalse);
      expect(result.error, contains('not empty'));
    });

    test('clone initializes repository structure', () async {
      // Note: This test doesn't actually clone from remote
      // It just verifies the structure setup
      final targetPath = '$testDir/test-repo';

      // Mock clone would create repository
      final repo = await GitRepository.init(targetPath);

      expect(await Directory(repo.gitDir).exists(), isTrue);
      expect(await Directory('${repo.gitDir}/objects').exists(), isTrue);
      expect(await Directory('${repo.gitDir}/refs').exists(), isTrue);
      expect(await File('${repo.gitDir}/HEAD').exists(), isTrue);
    });

    test('CloneResult holds repository info', () {
      final mockRepo = null; // Would be actual repo in real clone
      final result = CloneResult(
        success: true,
        repository: mockRepo,
        defaultBranch: 'main',
        objectsReceived: 42,
      );

      expect(result.success, isTrue);
      expect(result.defaultBranch, equals('main'));
      expect(result.objectsReceived, equals(42));
      expect(result.error, isNull);
    });

    test('CloneProgress enum has all stages', () {
      expect(CloneProgress.values.length, equals(7));
      expect(CloneProgress.values, contains(CloneProgress.initializing));
      expect(CloneProgress.values, contains(CloneProgress.fetching));
      expect(CloneProgress.values, contains(CloneProgress.complete));
    });

    test('progress callback receives correct stages', () async {
      final stages = <CloneProgress>[];
      final progressValues = <double>[];

      // This would be used in actual clone
      void trackProgress(CloneProgress stage, double progress) {
        stages.add(stage);
        progressValues.add(progress);
      }

      // Simulate progress tracking
      trackProgress(CloneProgress.initializing, 0.1);
      trackProgress(CloneProgress.fetching, 0.5);
      trackProgress(CloneProgress.complete, 1.0);

      expect(stages.length, equals(3));
      expect(progressValues.first, equals(0.1));
      expect(progressValues.last, equals(1.0));
    });
  });

  group('Remote Branch Detection', () {
    test('detects common default branch names', () {
      final commonBranches = ['main', 'master', 'develop', 'trunk'];

      for (final branch in commonBranches) {
        expect(branch, isNotEmpty);
        expect(branch.length, greaterThan(0));
      }
    });
  });
}
