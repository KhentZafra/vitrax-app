import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/hazard_service.dart';

/// Bottom sheet to choose up to [remaining] photos for a hazard (camera or
/// gallery). Returns the chosen files, or null if cancelled.
Future<List<File>?> showHazardPhotoPicker(BuildContext context, {required int remaining}) {
  return showModalBottomSheet<List<File>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xff141414),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _HazardPhotoPicker(remaining: remaining),
  );
}

class _HazardPhotoPicker extends StatefulWidget {
  final int remaining;
  const _HazardPhotoPicker({required this.remaining});

  @override
  State<_HazardPhotoPicker> createState() => _HazardPhotoPickerState();
}

class _HazardPhotoPickerState extends State<_HazardPhotoPicker> {
  final List<File> _files = [];
  final _picker = ImagePicker();

  int get _left => widget.remaining - _files.length;

  Future<void> _camera() async {
    if (_left <= 0) return;
    final x = await _picker.pickImage(source: ImageSource.camera, maxWidth: 1280, imageQuality: 75);
    if (x == null || !mounted) return;
    setState(() => _files.add(File(x.path)));
  }

  Future<void> _gallery() async {
    if (_left <= 0) return;
    final xs = await _picker.pickMultiImage(maxWidth: 1280, imageQuality: 75, limit: _left < 2 ? 2 : _left);
    if (!mounted) return;
    setState(() {
      for (final x in xs) {
        if (_files.length >= widget.remaining) break;
        _files.add(File(x.path));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade700, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('Add photos', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
              'Show others what the hazard looks like. ${_files.length}/${widget.remaining} selected.',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 13.5),
            ),
            const SizedBox(height: 4),
            Text('Please stop in a safe place before taking photos.', style: TextStyle(color: Colors.amber.shade300, fontSize: 12.5)),
            const SizedBox(height: 14),
            if (_files.isNotEmpty)
              SizedBox(
                height: 84,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _files.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => Stack(
                    children: [
                      ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.file(_files[i], width: 84, height: 84, fit: BoxFit.cover)),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: InkWell(
                          onTap: () => setState(() => _files.removeAt(i)),
                          child: Container(
                            decoration: const BoxDecoration(color: Colors.black87, shape: BoxShape.circle),
                            padding: const EdgeInsets.all(3),
                            child: const Icon(Icons.close, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_files.isNotEmpty) const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _left > 0 ? _camera : null,
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: const Text('Camera'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.blue, side: const BorderSide(color: Colors.blue), padding: const EdgeInsets.symmetric(vertical: 12)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _left > 0 ? _gallery : null,
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Gallery'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.blue, side: const BorderSide(color: Colors.blue), padding: const EdgeInsets.symmetric(vertical: 12)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _files.isEmpty ? null : () => Navigator.pop(context, List<File>.from(_files)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
                child: Text(_files.isEmpty ? 'Save photos' : 'Save ${_files.length} photo${_files.length == 1 ? '' : 's'}'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thumbnails of a hazard's photos; tap one to view it full screen.
/// Shows nothing when the hazard has no photos.
class HazardPhotoStrip extends StatefulWidget {
  final String hazardId;
  const HazardPhotoStrip({super.key, required this.hazardId});

  @override
  State<HazardPhotoStrip> createState() => _HazardPhotoStripState();
}

class _HazardPhotoStripState extends State<HazardPhotoStrip> {
  List<String> _urls = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final urls = await HazardService.photoUrls(widget.hazardId);
    if (!mounted) return;
    setState(() => _urls = urls);
  }

  void _open(int start) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(10),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Stack(
            children: [
              PageView.builder(
                controller: PageController(initialPage: start),
                itemCount: _urls.length,
                itemBuilder: (_, i) => InteractiveViewer(
                  child: Image.network(
                    _urls[i],
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => const Center(child: Icon(Icons.broken_image, color: Colors.white54, size: 40)),
                  ),
                ),
              ),
              Positioned(
                top: 6,
                right: 6,
                child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_urls.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        height: 64,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _urls.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => _open(i),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                _urls[i],
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(width: 64, height: 64, color: Colors.white10, child: const Icon(Icons.broken_image, color: Colors.white38, size: 20)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
