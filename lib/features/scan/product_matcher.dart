import 'dart:math' as math;

import '../../data/database.dart';
import '../../data/product_repository.dart';
import 'text_match.dart';

enum MatchKind { exact, similar, none }

class MatchResult {
  const MatchResult(this.kind, [this.product]);
  final MatchKind kind;
  final Product? product;
}

/// Finds the existing product a bill line belongs to. It only suggests;
/// the owner confirms "similar" matches on the review screen.
class ProductMatcher {
  ProductMatcher(this.products);
  final List<Product> products;

  static Set<String> _measures(String name) {
    final out = <String>{};
    final re = RegExp(r'(\d+(?:\.\d+)?)\s*(kg|gm|g|ml|ltr|l)\b');
    for (final m in re.allMatches(name.toLowerCase())) {
      var unit = m.group(2)!;
      if (unit == 'gm') {
        unit = 'g';
      }
      if (unit == 'ltr') {
        unit = 'l';
      }
      out.add('${m.group(1)}$unit');
    }
    return out;
  }

  MatchResult match(String billName) {
    final key = ProductRepository.keyOf(billName);
    final c = compact(billName);
    for (final p in products) {
      if (p.nameKey == key || (c.isNotEmpty && compact(p.name) == c)) {
        return MatchResult(MatchKind.exact, p);
      }
    }
    if (c.length < 3) {
      return const MatchResult(MatchKind.none);
    }
    final mine = _measures(billName);
    Product? best;
    var bestScore = 0.0;
    for (final p in products) {
      final theirs = _measures(p.name);
      if (mine.isNotEmpty &&
          theirs.isNotEmpty &&
          !(mine.length == theirs.length && mine.containsAll(theirs))) {
        continue; // different size: never the same product
      }
      final pc = compact(p.name);
      var score = similarity(c, pc);
      final shorter = c.length < pc.length ? c : pc;
      final longer = c.length < pc.length ? pc : c;
      if (shorter.length >= 4 && longer.contains(shorter)) {
        score = math.max(score, 0.85);
      }
      if (score > bestScore) {
        bestScore = score;
        best = p;
      }
    }
    if (best != null && bestScore >= 0.8) {
      return MatchResult(MatchKind.similar, best);
    }
    return const MatchResult(MatchKind.none);
  }
}
