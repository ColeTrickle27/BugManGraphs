import '../models/graph_shape.dart';
import 'pat_pattern.dart';

/// Exact text supplied by Library read on 2026-10-21. These are Graphs fills.
/// Raw file materialization remains blocked by Windows xattr support.
const graphPatSources = <GraphShapePattern, String>{
  GraphShapePattern.blockwork:
      '''*HBLOCKET, 440x215 BlockworkFree patterns from www.CADhatch.com
0,0,0, 0,450,440,-10
0,0,235, 0,450,440,-10
0,225,225, 0,450,440,-10
0,225,460, 0,450,440,-10
90,0,0, 0,450,-235,215
90,-10,0, 0,450,-235,215
90,225,225, 0,450,-235,215
90,215,225, 0,450,-235,215''',
  GraphShapePattern.brick: '''*HBSTRCES,Free patterns from www.CADhatch.com
0,0,0,0,75
90,0,0,225,112.5,75,-75''',
  GraphShapePattern.checkerplate:
      '''*HCHEQ1BS,Checkerplate 1 bar - Free patterns from www.CADhatch.com
0,0,0.8,0,1,0.4,-0.6
90,0.7,0.6,0,1,0.4,-0.6
90,0.2,0.1,0,1,0.4,-0.6
0,0.5,0.3,0,1,0.4,-0.6''',
};
const graphPatLibraryIds = <GraphShapePattern, String>{
  GraphShapePattern.blockwork: 'libfile_a469a7ba17e88191a09eca55ddbd107e',
  GraphShapePattern.brick: 'libfile_24da0359e30c8191bb267aef13166f08',
  GraphShapePattern.checkerplate: 'libfile_9d970993327c81918f3c96b81b1dbc68',
};
final graphPatPatterns =
    graphPatSources.map((key, value) => MapEntry(key, PatPattern.parse(value)));

/// Visual pattern density only; this never changes physical measurements.
const graphPatUnitScale = <GraphShapePattern, double>{
  GraphShapePattern.blockwork: 0.12,
  GraphShapePattern.brick: 0.24,
  GraphShapePattern.checkerplate: 32
};
