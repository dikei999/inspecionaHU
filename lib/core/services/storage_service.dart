import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../constants/app_dimensions.dart';
import 'supabase_service.dart';

class StorageService {
  StorageService._();

  static const String _bucketName = 'inspection-photos';
  static final _uuid = const Uuid();

  /// Comprime a foto para max 1280px / 75% JPEG / ~200KB.
  /// Retorna o arquivo comprimido.
  static Future<File> compressPhoto(File originalFile) async {
    final dir = await getTemporaryDirectory();
    final targetPath = '${dir.path}/${_uuid.v4()}.jpg';

    final result = await FlutterImageCompress.compressAndGetFile(
      originalFile.absolute.path,
      targetPath,
      minWidth: AppDimensions.photoMaxDimension,
      minHeight: AppDimensions.photoMaxDimension,
      quality: AppDimensions.photoJpegQuality,
      format: CompressFormat.jpeg,
    );

    if (result == null) {
      throw Exception('Falha ao comprimir a foto.');
    }
    return File(result.path);
  }

  /// Faz upload da foto e retorna a URL pública.
  /// Path: {hospitalId}/{inspectionId}/{uuid}.jpg
  static Future<String> uploadPhoto({
    required String hospitalId,
    required String inspectionId,
    required File file,
  }) async {
    final compressed = await compressPhoto(file);
    final fileName = '${_uuid.v4()}.jpg';
    final storagePath = '$hospitalId/$inspectionId/$fileName';

    await SupabaseService.storage
        .from(_bucketName)
        .upload(storagePath, compressed);

    return SupabaseService.storage
        .from(_bucketName)
        .getPublicUrl(storagePath);
  }

  /// Remove uma foto do storage pelo path.
  static Future<void> deletePhoto(String storagePath) async {
    await SupabaseService.storage.from(_bucketName).remove([storagePath]);
  }
}
