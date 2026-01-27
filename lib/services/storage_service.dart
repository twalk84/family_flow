// FILE: lib/services/storage_service.dart
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import '../firestore_paths.dart';

class StorageService {
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Uploads a file to Firebase Storage under the current family's folder.
  /// 
  /// [destinationPath] should be relative to the family root, e.g. "assignments/student123/my_scan.jpg"
  /// Returns the download URL.
  static Future<String> uploadFile({
    required File file,
    required String destinationPath,
  }) async {
    final familyId = FirestorePaths.familyId();
    final fullPath = 'families/$familyId/$destinationPath';
    
    final ref = _storage.ref().child(fullPath);
    final uploadTask = ref.putFile(file);
    final snapshot = await uploadTask;
    return await snapshot.ref.getDownloadURL();
  }

  static Future<void> deleteFile(String url) async {
    try {
      final ref = _storage.refFromURL(url);
      await ref.delete();
    } catch (e) {
      // Ignore if file doesn't exist or permission denied
    }
  }

  /// Specialized upload for assignment attachments.
  static Future<String> uploadAssignmentAttachment({
    required File file,
    required String studentId,
    required String assignmentId,
    required String fileName,
  }) async {
    try {
      final extension = fileName.split('.').last;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      // Standardizing on 'students/{id}/attachments/' which follows the profile_pic pattern
      final fullPath = 'students/$studentId/attachments/${assignmentId}_$timestamp.$extension';

      final ref = _storage.ref().child(fullPath);
      final uploadTask = ref.putFile(file);
      final snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw 'Permission denied to upload attachment. Please check Storage Security Rules.';
      }
      rethrow;
    } catch (e) {
      rethrow;
    }
  }
}
