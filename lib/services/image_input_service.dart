import 'dart:convert';
import 'dart:typed_data';

/// A photo picked from the camera or gallery.
class PickedImage {
  const PickedImage({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;
}

/// Abstraction over camera / gallery image picking.
///
/// Kept injectable so widget tests never depend on real device hardware —
/// the demo implementation returns a generated placeholder image instead.
abstract class ImageInputService {
  /// Returns the captured photo, or null when the user cancels / camera is
  /// unavailable.
  Future<PickedImage?> pickFromCamera();

  /// Returns the selected photo, or null when the user cancels.
  Future<PickedImage?> pickFromGallery();
}

/// Offline demo image source. It returns a tiny placeholder PNG (no camera
/// permissions, no file access, no raster thread) so the full screening
/// workflow — including widget tests — works without needing a camera or a
/// gallery.
class DemoImageInputService implements ImageInputService {
  @override
  Future<PickedImage?> pickFromCamera() async =>
      PickedImage(bytes: _kDemoPngBytes, name: 'demo-hive-photo.png');

  @override
  Future<PickedImage?> pickFromGallery() async =>
      PickedImage(bytes: _kDemoPngBytes, name: 'demo-hive-photo.png');
}

/// A valid 1x1 transparent PNG used as the demo placeholder photo. Generated
/// deterministically so widget tests never touch the real rasterizer.
final Uint8List _kDemoPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);