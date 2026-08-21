import 'package:flutter_test/flutter_test.dart';
import 'package:bible_app/services/qa_service.dart';

void main() {
  group('Q&A published 閘門（approved ≠ published）', () {
    test('已核准但沒有 published 欄位 → published 視為 false（學生端不可見）', () {
      final q = Question.fromDoc('id1', {
        'uid': 'u',
        'title': 't',
        'body': 'b',
        'category': '神學',
        'status': 'approved', // 已核准
        // 沒有 published 欄位
        'answer': {'content': 'ans', 'answered_at': 1, 'updated_at': 1},
        'created_at': 1,
        'updated_at': 1,
      });
      expect(q.status, 'approved');
      expect(q.published, isFalse); // 關鍵不變量：核准不等於發布
      expect(q.isAnswered, isTrue);
    });

    test('published:true 會被正確解析', () {
      final q = Question.fromDoc('id2', {
        'uid': 'u',
        'title': 't',
        'body': 'b',
        'category': '神學',
        'status': 'approved',
        'published': true,
        'answer': {'content': 'ans', 'answered_at': 1, 'updated_at': 1},
        'created_at': 1,
        'updated_at': 1,
      });
      expect(q.published, isTrue);
    });

    test('新提問預設未發布、未回答', () {
      final q = Question.fromDoc('id3', {
        'uid': 'u',
        'title': 't',
        'body': 'b',
        'category': '生活',
        'status': 'pending',
        'published': false,
        'created_at': 1,
        'updated_at': 1,
      });
      expect(q.published, isFalse);
      expect(q.isAnswered, isFalse);
    });
  });
}
