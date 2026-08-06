import 'dart:io';

/// §7.6: fail below 100% line coverage on lib/domain/ and lib/state/.
void main() {
  final lcov = File('coverage/lcov.info').readAsLinesSync();
  String? currentFile;
  var relevant = false;
  var found = 0;
  var hit = 0;
  final misses = <String>[];

  for (final line in lcov) {
    if (line.startsWith('SF:')) {
      currentFile = line.substring(3);
      relevant = (currentFile.contains('lib/domain/') ||
              currentFile.contains('lib/state/')) &&
          !currentFile.endsWith('.g.dart');
    } else if (relevant && line.startsWith('DA:')) {
      final parts = line.substring(3).split(',');
      found++;
      if (int.parse(parts[1]) > 0) {
        hit++;
      } else {
        misses.add('$currentFile:${parts[0]}');
      }
    }
  }

  if (found == 0) {
    stderr.writeln('coverage_gate: no domain/state lines found in lcov.info');
    exit(1);
  }
  if (hit < found) {
    stderr.writeln('coverage_gate: ${found - hit} uncovered lines:');
    misses.forEach(stderr.writeln);
    exit(1);
  }
  stdout.writeln('coverage_gate: 100% ($hit/$found lines) on domain/ + state/');
}
