import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:math';

void main() {
  runApp(VideoEditorApp());
}

class VideoSegment {
  final String id;
  double startTime;
  double endTime;
  bool isSelected;
  bool isDeleted;
  Color color;

  VideoSegment({
    required this.id,
    required this.startTime,
    required this.endTime,
    this.isSelected = false,
    this.isDeleted = false,
    Color? color,
  }) : color = color ?? _generateRandomColor();

  double get duration => endTime - startTime;

  static Color _generateRandomColor() {
    final colors = [
      Colors.blue[300]!,
      Colors.green[300]!,
      Colors.orange[300]!,
      Colors.purple[300]!,
      Colors.red[300]!,
      Colors.cyan[300]!,
      Colors.pink[300]!,
      Colors.teal[300]!,
    ];
    return colors[Random().nextInt(colors.length)];
  }

  VideoSegment copyWith({
    String? id,
    double? startTime,
    double? endTime,
    bool? isSelected,
    bool? isDeleted,
    Color? color,
  }) {
    return VideoSegment(
      id: id ?? this.id,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isSelected: isSelected ?? this.isSelected,
      isDeleted: isDeleted ?? this.isDeleted,
      color: color ?? this.color,
    );
  }
}

class VideoEditorApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pro Video Editor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Color(0xFF0A0A0A),
        appBarTheme: AppBarTheme(
          backgroundColor: Color(0xFF1A1A1A),
          elevation: 0,
        ),
        cardTheme: CardThemeData(color: Color(0xFF1E1E1E), elevation: 8),
      ),
      home: VideoEditorHomePage(),
    );
  }
}

class VideoEditorHomePage extends StatefulWidget {
  @override
  _VideoEditorHomePageState createState() => _VideoEditorHomePageState();
}

class _VideoEditorHomePageState extends State<VideoEditorHomePage>
    with TickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _isPlaying = false;
  double _totalDuration = 0.0;
  File? _videoFile;
  bool _isLoading = false;
  List<VideoSegment> _segments = [];
  double _playbackSpeed = 1.0;
  bool _skipMode = false;
  int? _selectedSegmentIndex;
  double _currentPosition = 0.0;

  // Animation controllers
  late AnimationController _pulseController;
  late AnimationController _slideController;
  late Animation<double> _pulseAnimation;
  late Animation<Offset> _slideAnimation;

  // UI States
  bool _showAdvancedControls = false;
  String _currentAction = 'Ready';

  @override
  void initState() {
    super.initState();
    _initAnimations();
  }

  void _initAnimations() {
    _pulseController = AnimationController(
      duration: Duration(milliseconds: 1000),
      vsync: this,
    )..repeat(reverse: true);

    _slideController = AnimationController(
      duration: Duration(milliseconds: 300),
      vsync: this,
    );

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _slideAnimation = Tween<Offset>(begin: Offset(0, 1), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _slideController, curve: Curves.elasticOut),
        );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _pulseController.dispose();
    _slideController.dispose();
    super.dispose();
  }

  // ==================== IMPORT FUNCTIONALITY ====================
  Future<void> _importVideo() async {
    _updateAction('Importing video...');
    setState(() => _isLoading = true);

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        // allowedExtensions: ['mp4', 'mov', 'avi', 'mkv', 'webm'],
      );

      if (result != null && result.files.single.path != null) {
        _videoFile = File(result.files.single.path!);
        await _initializeVideo();
        _createInitialSegment();
        _slideController.forward();
        _showSuccessDialog('✅ Video imported successfully!');
      }
    } catch (e) {
      _showErrorDialog('❌ Import failed', e.toString());
    } finally {
      setState(() => _isLoading = false);
      _updateAction('Ready');
    }
  }

  Future<void> _initializeVideo() async {
    if (_videoFile == null) return;

    _controller?.dispose();
    _controller = VideoPlayerController.file(_videoFile!);
    await _controller!.initialize();

    setState(() {
      _totalDuration = _controller!.value.duration.inMilliseconds.toDouble();
    });

    _controller!.addListener(_videoListener);
  }

  void _createInitialSegment() {
    setState(() {
      _segments = [
        VideoSegment(
          id: 'initial_${DateTime.now().millisecondsSinceEpoch}',
          startTime: 0.0,
          endTime: _totalDuration,
        ),
      ];
    });
  }

  void _videoListener() {
    if (!mounted || _controller == null) return;

    setState(() {
      _isPlaying = _controller!.value.isPlaying;
      _currentPosition = _controller!.value.position.inMilliseconds.toDouble();
    });

    if (_skipMode && _controller!.value.isPlaying) {
      _handleSkipPlayback();
    }
  }

  // ==================== SPLIT/DELETE FUNCTIONALITY ====================
  void _splitSegmentAtCurrentPosition() {
    if (_controller == null || _selectedSegmentIndex == null) {
      _showErrorDialog(
        '⚠️ Selection Required',
        'Please select a segment first',
      );
      return;
    }

    VideoSegment selectedSegment = _segments[_selectedSegmentIndex!];
    double currentPos = _currentPosition;

    if (currentPos <= selectedSegment.startTime + 500 ||
        currentPos >= selectedSegment.endTime - 500) {
      _showErrorDialog(
        '⚠️ Invalid Split Position',
        'Position must be at least 0.5s from segment boundaries',
      );
      return;
    }

    _updateAction('Splitting segment...');

    setState(() {
      VideoSegment firstPart = selectedSegment.copyWith(
        id: 'split_${DateTime.now().millisecondsSinceEpoch}_1',
        endTime: currentPos,
      );

      VideoSegment secondPart = selectedSegment.copyWith(
        id: 'split_${DateTime.now().millisecondsSinceEpoch}_2',
        startTime: currentPos,
      );

      _segments.removeAt(_selectedSegmentIndex!);
      _segments.insert(_selectedSegmentIndex!, firstPart);
      _segments.insert(_selectedSegmentIndex! + 1, secondPart);

      _selectedSegmentIndex = null;
    });

    _showSuccessDialog('✂️ Segment split successfully!');
    _updateAction('Ready');
    HapticFeedback.mediumImpact();
  }

  void _deleteSegment(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange),
            SizedBox(width: 10),
            Text('Delete Segment?', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'This will permanently remove the segment.',
              style: TextStyle(color: Colors.white70),
            ),
            SizedBox(height: 10),
            Container(
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Duration: ${_formatDuration(_segments[index].duration)}',
                style: TextStyle(color: Colors.red[300]),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _performDelete(index);
            },
            icon: Icon(Icons.delete),
            label: Text('Delete'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _performDelete(int index) {
    _updateAction('Deleting segment...');

    setState(() {
      _segments[index] = _segments[index].copyWith(isDeleted: true);
      if (_selectedSegmentIndex == index) {
        _selectedSegmentIndex = null;
      }
    });

    _showSuccessDialog('🗑️ Segment deleted successfully!');
    _updateAction('Ready');
    HapticFeedback.heavyImpact();
  }

  void _restoreSegment(int index) {
    setState(() {
      _segments[index] = _segments[index].copyWith(isDeleted: false);
    });
    _showSuccessDialog('↩️ Segment restored!');
    HapticFeedback.lightImpact();
  }

  // ==================== SKIP PLAYBACK FUNCTIONALITY ====================
  void _toggleSkipMode() {
    setState(() {
      _skipMode = !_skipMode;
    });

    String message = _skipMode
        ? '⏭️ Skip mode enabled - will skip deleted segments'
        : '▶️ Normal playback mode';

    _showSuccessDialog(message);
    _updateAction(_skipMode ? 'Skip mode active' : 'Ready');
    HapticFeedback.selectionClick();
  }

  void _handleSkipPlayback() {
    if (_controller == null || !_controller!.value.isPlaying) return;

    final currentPos = _currentPosition;

    // Find the current segment by checking which segment contains current position
    VideoSegment? currentSegment;
    int currentSegmentIndex = -1;

    for (int i = 0; i < _segments.length; i++) {
      if (currentPos >= _segments[i].startTime &&
          currentPos < _segments[i].endTime) {
        currentSegment = _segments[i];
        currentSegmentIndex = i;
        break;
      }
    }

    // If we're in a deleted segment, find the next non-deleted segment
    if (currentSegment != null && currentSegment.isDeleted) {
      VideoSegment? nextSegment;

      // Look for the next non-deleted segment after the current one
      for (int i = currentSegmentIndex + 1; i < _segments.length; i++) {
        if (!_segments[i].isDeleted) {
          nextSegment = _segments[i];
          break;
        }
      }

      if (nextSegment != null) {
        print(
          'Skip: Jumping from ${_formatDuration(currentPos)} to ${_formatDuration(nextSegment.startTime)}',
        );
        _controller!.seekTo(
          Duration(milliseconds: nextSegment.startTime.toInt()),
        );
        _showSuccessDialog('⏭️ Skipped to next segment');
      } else {
        // No more non-deleted segments, stop playback
        _controller!.pause();
        _showSuccessDialog('🏁 Reached end - no more active segments');
      }
    }
    // Also check if we've reached the end of a non-deleted segment and the next segment is deleted
    else if (currentSegment != null && !currentSegment.isDeleted) {
      // Check if we're near the end of current segment (within 100ms)
      if (currentPos >= currentSegment.endTime - 100) {
        // Check if next segment exists and is deleted
        if (currentSegmentIndex + 1 < _segments.length &&
            _segments[currentSegmentIndex + 1].isDeleted) {
          // Find next non-deleted segment
          VideoSegment? nextNonDeletedSegment;
          for (int i = currentSegmentIndex + 2; i < _segments.length; i++) {
            if (!_segments[i].isDeleted) {
              nextNonDeletedSegment = _segments[i];
              break;
            }
          }

          if (nextNonDeletedSegment != null) {
            print(
              'Preemptive skip: Jumping to ${_formatDuration(nextNonDeletedSegment.startTime)}',
            );
            _controller!.seekTo(
              Duration(milliseconds: nextNonDeletedSegment.startTime.toInt()),
            );
            _showSuccessDialog('⏭️ Skipped deleted segment');
          } else {
            _controller!.pause();
            _showSuccessDialog('🏁 Reached end - no more active segments');
          }
        }
      }
    }
  }

  void _setPlaybackSpeed(double speed) {
    setState(() {
      _playbackSpeed = speed;
    });
    _controller?.setPlaybackSpeed(speed);
    _showSuccessDialog('🏃 Playback speed: ${speed}x');
    HapticFeedback.selectionClick();
  }

  // ==================== EXPORT FUNCTIONALITY ====================
  Future<void> _showExportOptions() async {
    List<VideoSegment> activeSegments = _segments
        .where((s) => !s.isDeleted)
        .toList();
    List<VideoSegment> selectedSegments = activeSegments
        .where((s) => s.isSelected)
        .toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Color(0xFF2A2A2A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: EdgeInsets.symmetric(vertical: 10),
              height: 4,
              width: 50,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    '📤 Export Options',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(height: 20),

                  _buildExportOption(
                    icon: Icons.video_library,
                    title: 'Export All Segments',
                    subtitle: '${activeSegments.length} active segments',
                    duration: _getTotalDuration(activeSegments),
                    onTap: () {
                      Navigator.pop(context);
                      _performExport(activeSegments, 'All Segments');
                    },
                  ),

                  SizedBox(height: 10),

                  _buildExportOption(
                    icon: Icons.check_box,
                    title: 'Export Selected Only',
                    subtitle: '${selectedSegments.length} selected segments',
                    duration: _getTotalDuration(selectedSegments),
                    onTap: selectedSegments.isNotEmpty
                        ? () {
                            Navigator.pop(context);
                            _performExport(
                              selectedSegments,
                              'Selected Segments',
                            );
                          }
                        : null,
                  ),

                  SizedBox(height: 10),

                  _buildExportOption(
                    icon: Icons.settings,
                    title: 'Custom Export',
                    subtitle: 'Choose quality & format',
                    duration: _getTotalDuration(activeSegments),
                    onTap: () {
                      Navigator.pop(context);
                      _showCustomExportDialog();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required double duration,
    required VoidCallback? onTap,
  }) {
    return Card(
      color: onTap != null ? Color(0xFF3A3A3A) : Color(0xFF2A2A2A),
      child: ListTile(
        enabled: onTap != null,
        onTap: onTap,
        leading: Container(
          padding: EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: onTap != null
                ? Colors.blue.withOpacity(0.2)
                : Colors.grey.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: onTap != null ? Colors.blue : Colors.grey),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: onTap != null ? Colors.white : Colors.grey,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle, style: TextStyle(color: Colors.grey[400])),
            Text(
              'Duration: ${_formatDuration(duration)}',
              style: TextStyle(color: Colors.blue[300], fontSize: 12),
            ),
          ],
        ),
        trailing: Icon(
          Icons.arrow_forward_ios,
          color: onTap != null ? Colors.blue : Colors.grey,
        ),
      ),
    );
  }

  void _showCustomExportDialog() {
    String selectedQuality = 'HD (720p)';
    String selectedFormat = 'MP4';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Color(0xFF2A2A2A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            '🎬 Custom Export Settings',
            style: TextStyle(color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedQuality,
                decoration: InputDecoration(
                  labelText: 'Quality',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[600]!),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                dropdownColor: Color(0xFF3A3A3A),
                style: TextStyle(color: Colors.white),
                items:
                    ['4K (2160p)', 'Full HD (1080p)', 'HD (720p)', 'SD (480p)']
                        .map(
                          (quality) => DropdownMenuItem(
                            value: quality,
                            child: Text(quality),
                          ),
                        )
                        .toList(),
                onChanged: (value) {
                  setDialogState(() => selectedQuality = value!);
                },
              ),
              SizedBox(height: 15),
              DropdownButtonFormField<String>(
                value: selectedFormat,
                decoration: InputDecoration(
                  labelText: 'Format',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[600]!),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                dropdownColor: Color(0xFF3A3A3A),
                style: TextStyle(color: Colors.white),
                items: ['MP4', 'MOV', 'AVI', 'MKV']
                    .map(
                      (format) =>
                          DropdownMenuItem(value: format, child: Text(format)),
                    )
                    .toList(),
                onChanged: (value) {
                  setDialogState(() => selectedFormat = value!);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                List<VideoSegment> activeSegments = _segments
                    .where((s) => !s.isDeleted)
                    .toList();
                _performExport(
                  activeSegments,
                  'Custom ($selectedQuality, $selectedFormat)',
                );
              },
              icon: Icon(Icons.video_settings),
              label: Text('Export'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _performExport(
    List<VideoSegment> segments,
    String exportType,
  ) async {
    if (segments.isEmpty) {
      _showErrorDialog(
        '⚠️ No segments to export',
        'Please select at least one segment',
      );
      return;
    }

    _updateAction('Exporting video...');
    setState(() => _isLoading = true);

    try {
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${directory.path}/video_export_$timestamp.txt');

      StringBuffer exportData = StringBuffer();
      exportData.writeln('🎬 VIDEO EXPORT CONFIGURATION');
      exportData.writeln('=================================');
      exportData.writeln('Export Type: $exportType');
      exportData.writeln('Source File: ${_videoFile?.path}');
      exportData.writeln(
        'Original Duration: ${_formatDuration(_totalDuration)}',
      );
      exportData.writeln('Export Segments: ${segments.length}');
      exportData.writeln(
        'Total Export Duration: ${_formatDuration(_getTotalDuration(segments))}',
      );
      exportData.writeln('Export Date: ${DateTime.now()}');
      exportData.writeln('');
      exportData.writeln('SEGMENT DETAILS:');
      exportData.writeln('================');

      for (int i = 0; i < segments.length; i++) {
        VideoSegment segment = segments[i];
        exportData.writeln('Segment ${i + 1}: ${segment.id}');
        exportData.writeln(
          '  Start Time: ${_formatDuration(segment.startTime)}',
        );
        exportData.writeln('  End Time: ${_formatDuration(segment.endTime)}');
        exportData.writeln('  Duration: ${_formatDuration(segment.duration)}');
        exportData.writeln('  Selected: ${segment.isSelected ? "Yes" : "No"}');
        exportData.writeln('');
      }

      exportData.writeln('FFmpeg Command (example):');
      exportData.writeln('========================');
      for (int i = 0; i < segments.length; i++) {
        VideoSegment segment = segments[i];
        double startSeconds = segment.startTime / 1000;
        double durationSeconds = segment.duration / 1000;
        exportData.writeln(
          'ffmpeg -i input.mp4 -ss $startSeconds -t $durationSeconds -c copy output_part${i + 1}.mp4',
        );
      }

      await file.writeAsString(exportData.toString());

      setState(() => _isLoading = false);
      _updateAction('Ready');

      _showExportCompleteDialog(file, exportType, segments.length);
    } catch (e) {
      setState(() => _isLoading = false);
      _updateAction('Ready');
      _showErrorDialog('❌ Export failed', e.toString());
    }
  }

  void _showExportCompleteDialog(
    File file,
    String exportType,
    int segmentCount,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Icon(Icons.check_circle, color: Colors.green, size: 30),
            ),
            SizedBox(width: 10),
            Text('Export Complete!', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '✅ Successfully exported $exportType',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              '📊 Segments: $segmentCount',
              style: TextStyle(color: Colors.white70),
            ),
            Text(
              '📁 Location: ${file.path}',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            SizedBox(height: 15),
            Container(
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '💡 In production, this would trigger FFmpeg processing to create the actual video file.',
                style: TextStyle(color: Colors.blue[300], fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _shareFile(file);
            },
            icon: Icon(Icons.share),
            label: Text('Share Config'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== OPEN/SHARE FUNCTIONALITY ====================
  Future<void> _shareFile(File file) async {
    try {
      await Share.shareXFiles([
        XFile(file.path),
      ], text: 'Video Export Configuration');
      _showSuccessDialog('📤 Export configuration shared!');
    } catch (e) {
      _showErrorDialog('❌ Share failed', e.toString());
    }
  }

  Future<void> _shareVideoInfo() async {
    if (_videoFile == null) {
      _showErrorDialog('⚠️ No video loaded', 'Please import a video first');
      return;
    }

    try {
      List<VideoSegment> activeSegments = _segments
          .where((s) => !s.isDeleted)
          .toList();

      StringBuffer shareText = StringBuffer();
      shareText.writeln('🎬 Video Edit Summary');
      shareText.writeln('====================');
      shareText.writeln(
        'Original Duration: ${_formatDuration(_totalDuration)}',
      );
      shareText.writeln('Total Segments: ${_segments.length}');
      shareText.writeln('Active Segments: ${activeSegments.length}');
      shareText.writeln(
        'Export Duration: ${_formatDuration(_getTotalDuration(activeSegments))}',
      );
      shareText.writeln('');
      shareText.writeln('Created with Pro Video Editor');

      await Share.share(shareText.toString(), subject: 'Video Edit Summary');
      _showSuccessDialog('📤 Video info shared!');
    } catch (e) {
      _showErrorDialog('❌ Share failed', e.toString());
    }
  }

  void _openVideoInfo() {
    if (_videoFile == null) return;

    List<VideoSegment> activeSegments = _segments
        .where((s) => !s.isDeleted)
        .toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue),
            SizedBox(width: 10),
            Text('📹 Video Information', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow('📁 File', _videoFile!.path.split('/').last),
              _buildInfoRow('📍 Path', _videoFile!.path),
              _buildInfoRow('⏱️ Duration', _formatDuration(_totalDuration)),
              _buildInfoRow('📊 Total Segments', '${_segments.length}'),
              _buildInfoRow('✅ Active Segments', '${activeSegments.length}'),
              _buildInfoRow(
                '🗑️ Deleted Segments',
                '${_segments.length - activeSegments.length}',
              ),
              if (_controller != null) ...[
                _buildInfoRow(
                  '📐 Resolution',
                  '${_controller!.value.size.width.toInt()}×${_controller!.value.size.height.toInt()}',
                ),
                _buildInfoRow(
                  '📏 Aspect Ratio',
                  _controller!.value.aspectRatio.toStringAsFixed(2),
                ),
              ],
              _buildInfoRow(
                '🎯 Export Duration',
                _formatDuration(_getTotalDuration(activeSegments)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _shareVideoInfo();
            },
            icon: Icon(Icons.share),
            label: Text('Share Info'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== PLAYBACK CONTROLS ====================
  void _togglePlayback() {
    if (_controller == null) return;

    if (_controller!.value.isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
    HapticFeedback.selectionClick();
  }

  void _seekToPosition(double position) {
    if (_controller == null) return;
    _controller!.seekTo(Duration(milliseconds: position.toInt()));
  }

  // ==================== UTILITY FUNCTIONS ====================
  String _formatDuration(double milliseconds) {
    Duration duration = Duration(milliseconds: milliseconds.toInt());
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return "${twoDigits(duration.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  double _getTotalDuration(List<VideoSegment> segments) {
    return segments.fold(0.0, (sum, segment) => sum + segment.duration);
  }

  void _updateAction(String action) {
    setState(() {
      _currentAction = action;
    });
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 10),
            Text(title, style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(message, style: TextStyle(color: Colors.white70)),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.white),
            SizedBox(width: 10),
            Expanded(
              child: Text(message, style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // ==================== UI BUILD METHODS ====================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A0A0A), Color(0xFF1A1A1A)],
          ),
        ),
        child: SafeArea(
          child: _isLoading
              ? _buildLoadingScreen()
              : _controller == null
              ? _buildWelcomeScreen()
              : _buildEditorScreen(),
        ),
      ),
    );
  }

  Widget _buildLoadingScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue, Colors.purple],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(40),
              ),
              child: Icon(Icons.video_library, size: 40, color: Colors.white),
            ),
          ),
          SizedBox(height: 30),
          Text(
            _currentAction,
            style: TextStyle(
              fontSize: 18,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 20),
          Container(
            width: 200,
            child: LinearProgressIndicator(
              backgroundColor: Colors.grey[800],
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue, Colors.purple, Colors.pink],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(60),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.3),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Icon(Icons.video_library, size: 60, color: Colors.white),
            ),
          ),
          SizedBox(height: 40),
          Text(
            'Pro Video Editor',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Professional video editing made simple',
            style: TextStyle(fontSize: 16, color: Colors.white70),
          ),
          SizedBox(height: 30),
          Container(
            padding: EdgeInsets.all(20),
            margin: EdgeInsets.symmetric(horizontal: 40),
            decoration: BoxDecoration(
              color: Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.blue.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                _buildFeatureItem('📁', 'Import', 'Load videos from device'),
                _buildFeatureItem(
                  '✂️',
                  'Split/Delete',
                  'Cut and remove segments',
                ),
                _buildFeatureItem(
                  '⏭️',
                  'Skip Playback',
                  'Preview final result',
                ),
                _buildFeatureItem('💾', 'Export', 'Save your edits'),
                _buildFeatureItem('📤', 'Open/Share', 'Share your creations'),
              ],
            ),
          ),
          SizedBox(height: 40),
          Container(
            width: 200,
            height: 60,
            child: ElevatedButton.icon(
              onPressed: _importVideo,
              icon: Icon(Icons.file_upload, size: 28),
              label: Text(
                'Import Video',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                elevation: 10,
                shadowColor: Colors.blue.withOpacity(0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(String emoji, String title, String description) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Text(emoji, style: TextStyle(fontSize: 24)),
          SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditorScreen() {
    return Column(
      children: [
        // Top App Bar
        _buildTopAppBar(),

        // Video Player
        Expanded(flex: 4, child: _buildVideoPlayer()),

        // Timeline and Segments
        _buildTimelineSection(),

        // Control Panel
        _buildControlPanel(),

        // Bottom Action Bar
        _buildBottomActionBar(),
      ],
    );
  }

  Widget _buildTopAppBar() {
    return Container(
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Color(0xFF1A1A1A),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Text(
            'Pro Video Editor',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Spacer(),
          Text(
            _currentAction,
            style: TextStyle(
              fontSize: 12,
              color: _currentAction == 'Ready' ? Colors.green : Colors.orange,
            ),
          ),
          SizedBox(width: 15),
          _buildTopMenuButton(),
        ],
      ),
    );
  }

  Widget _buildTopMenuButton() {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: Colors.white),
      color: Color(0xFF2A2A2A),
      onSelected: (value) {
        switch (value) {
          case 'info':
            _openVideoInfo();
            break;
          case 'share':
            _shareVideoInfo();
            break;
          case 'speed':
            _showSpeedDialog();
            break;
          case 'advanced':
            setState(() => _showAdvancedControls = !_showAdvancedControls);
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'info',
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.white),
              SizedBox(width: 10),
              Text('Video Info', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'share',
          child: Row(
            children: [
              Icon(Icons.share, color: Colors.white),
              SizedBox(width: 10),
              Text('Share Info', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'speed',
          child: Row(
            children: [
              Icon(Icons.speed, color: Colors.white),
              SizedBox(width: 10),
              Text('Playback Speed', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'advanced',
          child: Row(
            children: [
              Icon(Icons.settings, color: Colors.white),
              SizedBox(width: 10),
              Text('Advanced Controls', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ],
    );
  }

  void _showSpeedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF2A2A2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('🏃 Playback Speed', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((speed) {
            return ListTile(
              title: Text('${speed}x', style: TextStyle(color: Colors.white)),
              leading: Radio<double>(
                value: speed,
                groupValue: _playbackSpeed,
                onChanged: (value) {
                  Navigator.pop(context);
                  _setPlaybackSpeed(value!);
                },
                activeColor: Colors.blue,
              ),
              onTap: () {
                Navigator.pop(context);
                _setPlaybackSpeed(speed);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      margin: EdgeInsets.all(15),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: VideoPlayer(_controller!),
            ),
            if (!_isPlaying)
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: IconButton(
                  onPressed: _togglePlayback,
                  icon: Icon(Icons.play_arrow, size: 50, color: Colors.white),
                ),
              ),
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(
                  '${_playbackSpeed}x',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
            if (_skipMode)
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Text(
                    'SKIP MODE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineSection() {
    return Container(
      height: 200,
      color: Color(0xFF1E1E1E),
      child: Column(
        children: [
          // Segments Header
          Padding(
            padding: EdgeInsets.all(15),
            child: Row(
              children: [
                Text(
                  'Segments (${_segments.where((s) => !s.isDeleted).length}/${_segments.length})',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Spacer(),
                if (_segments.any((s) => s.isDeleted))
                  TextButton.icon(
                    onPressed: () {
                      setState(() {
                        for (int i = 0; i < _segments.length; i++) {
                          if (_segments[i].isDeleted) {
                            _segments[i] = _segments[i].copyWith(
                              isDeleted: false,
                            );
                          }
                        }
                      });
                      _showSuccessDialog('↩️ All segments restored!');
                    },
                    icon: Icon(Icons.restore, size: 16, color: Colors.orange),
                    label: Text(
                      'Restore All',
                      style: TextStyle(color: Colors.orange),
                    ),
                  ),
              ],
            ),
          ),

          // Segments List
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 15),
              itemCount: _segments.length,
              itemBuilder: (context, index) => _buildSegmentCard(index),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentCard(int index) {
    VideoSegment segment = _segments[index];
    bool isSelected = _selectedSegmentIndex == index;

    return GestureDetector(
      onTap: () {
        setState(() {
          if (segment.isDeleted) return;
          _selectedSegmentIndex = isSelected ? null : index;
        });
        HapticFeedback.selectionClick();

        if (!isSelected && !segment.isDeleted) {
          _seekToPosition(segment.startTime);
        }
      },
      onLongPress: () {
        if (!segment.isDeleted) {
          _deleteSegment(index);
        }
      },
      child: AnimatedContainer(
        duration: Duration(milliseconds: 300),
        width: 140,
        margin: EdgeInsets.only(right: 10, bottom: 10),
        decoration: BoxDecoration(
          color: segment.isDeleted
              ? Colors.red.withOpacity(0.2)
              : isSelected
              ? Colors.blue.withOpacity(0.3)
              : Color(0xFF2A2A2A),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: segment.isDeleted
                ? Colors.red
                : isSelected
                ? Colors.blue
                : Colors.transparent,
            width: 2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.3),
                    blurRadius: 10,
                    spreadRadius: 2,
                  ),
                ]
              : [],
        ),
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: segment.isDeleted ? Colors.red : segment.color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Segment ${index + 1}',
                      style: TextStyle(
                        color: segment.isDeleted
                            ? Colors.red[300]
                            : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 8),
              Text(
                _formatDuration(segment.duration),
                style: TextStyle(
                  color: segment.isDeleted ? Colors.red[200] : Colors.white70,
                  fontSize: 10,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '${_formatDuration(segment.startTime)} → ${_formatDuration(segment.endTime)}',
                style: TextStyle(
                  color: segment.isDeleted ? Colors.red[100] : Colors.white60,
                  fontSize: 8,
                ),
              ),
              Spacer(),
              Row(
                children: [
                  if (segment.isDeleted)
                    GestureDetector(
                      onTap: () => _restoreSegment(index),
                      child: Container(
                        padding: EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.restore,
                          size: 12,
                          color: Colors.orange,
                        ),
                      ),
                    )
                  else ...[
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          segment.isSelected = !segment.isSelected;
                        });
                        HapticFeedback.lightImpact();
                      },
                      child: Container(
                        padding: EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: segment.isSelected
                              ? Colors.green.withOpacity(0.2)
                              : Colors.grey.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          segment.isSelected
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          size: 12,
                          color: segment.isSelected
                              ? Colors.green
                              : Colors.grey,
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _deleteSegment(index),
                      child: Container(
                        padding: EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.delete_outline,
                          size: 12,
                          color: Colors.red,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlPanel() {
    return Container(
      padding: EdgeInsets.all(15),
      color: Color(0xFF2A2A2A),
      child: Column(
        children: [
          // Playback Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildControlButton(
                icon: Icons.skip_previous,
                onPressed: () => _seekToPosition(0),
                tooltip: 'Go to Start',
              ),
              SizedBox(width: 20),
              _buildControlButton(
                icon: _isPlaying ? Icons.pause : Icons.play_arrow,
                onPressed: _togglePlayback,
                tooltip: _isPlaying ? 'Pause' : 'Play',
                isPrimary: true,
              ),
              SizedBox(width: 20),
              _buildControlButton(
                icon: Icons.skip_next,
                onPressed: () => _seekToPosition(_totalDuration),
                tooltip: 'Go to End',
              ),
            ],
          ),

          SizedBox(height: 15),

          // Timeline
          if (_controller != null && _controller!.value.isInitialized)
            Container(
              height: 4,
              child: VideoProgressIndicator(
                _controller!,
                allowScrubbing: true,
                colors: VideoProgressColors(
                  playedColor: Colors.blue,
                  bufferedColor: Colors.grey[600]!,
                  backgroundColor: Colors.grey[800]!,
                ),
              ),
            ),

          SizedBox(height: 15),

          // Position and Duration
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(_currentPosition),
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                '${_playbackSpeed}x ${_skipMode ? "• SKIP MODE" : ""}',
                style: TextStyle(
                  color: _skipMode ? Colors.orange : Colors.white70,
                  fontSize: 12,
                  fontWeight: _skipMode ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              Text(
                _formatDuration(_totalDuration),
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),

          // Advanced Controls
          if (_showAdvancedControls) ...[
            SizedBox(height: 15),
            Divider(color: Colors.grey[700]),
            SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildAdvancedButton(
                  icon: Icons.fast_rewind,
                  label: '-10s',
                  onPressed: () {
                    double newPos = (_currentPosition - 10000).clamp(
                      0,
                      _totalDuration,
                    );
                    _seekToPosition(newPos);
                  },
                ),
                _buildAdvancedButton(
                  icon: Icons.fast_forward,
                  label: '+10s',
                  onPressed: () {
                    double newPos = (_currentPosition + 10000).clamp(
                      0,
                      _totalDuration,
                    );
                    _seekToPosition(newPos);
                  },
                ),
                _buildAdvancedButton(
                  icon: Icons.filter_frames,
                  label: 'Frame',
                  onPressed: () {
                    // Frame by frame would require custom implementation
                    _showSuccessDialog(
                      '🎬 Frame control (requires custom player)',
                    );
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onPressed,
    required String tooltip,
    bool isPrimary = false,
  }) {
    return Container(
      width: isPrimary ? 60 : 50,
      height: isPrimary ? 60 : 50,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? Colors.blue : Colors.grey[700],
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(isPrimary ? 30 : 25),
          ),
          padding: EdgeInsets.zero,
          elevation: isPrimary ? 8 : 4,
        ),
        child: Icon(icon, size: isPrimary ? 30 : 24),
      ),
    );
  }

  Widget _buildAdvancedButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Column(
      children: [
        IconButton(
          onPressed: onPressed,
          icon: Icon(icon, color: Colors.white70),
          iconSize: 20,
        ),
        Text(label, style: TextStyle(color: Colors.white70, fontSize: 10)),
      ],
    );
  }

  Widget _buildBottomActionBar() {
    return Container(
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Color(0xFF1A1A1A),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildActionButton(
            icon: Icons.file_upload,
            label: 'Import',
            onPressed: _importVideo,
            color: Colors.blue,
            tooltip: 'Import new video',
          ),
          _buildActionButton(
            icon: Icons.content_cut,
            label: 'Split',
            onPressed: _selectedSegmentIndex != null
                ? _splitSegmentAtCurrentPosition
                : null,
            color: Colors.orange,
            tooltip: 'Split selected segment',
          ),
          _buildActionButton(
            icon: Icons.skip_next,
            label: 'Skip',
            onPressed: _toggleSkipMode,
            color: _skipMode ? Colors.orange : Colors.grey,
            tooltip: 'Toggle skip mode',
          ),
          _buildActionButton(
            icon: Icons.save_alt,
            label: 'Export',
            onPressed: _showExportOptions,
            color: Colors.green,
            tooltip: 'Export video',
          ),
          _buildActionButton(
            icon: Icons.share,
            label: 'Share',
            onPressed: _shareVideoInfo,
            color: Colors.purple,
            tooltip: 'Share video info',
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required Color color,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 50,
            height: 50,
            child: ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: onPressed != null ? color : Colors.grey[700],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
                padding: EdgeInsets.zero,
                elevation: onPressed != null ? 6 : 2,
              ),
              child: Icon(icon, size: 24),
            ),
          ),
          SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              color: onPressed != null ? color : Colors.grey,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
