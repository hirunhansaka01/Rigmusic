import 'package:flutter/material.dart';
import '../data/chord_library.dart';
import '../theme/app_colors.dart';
import '../services/reference_tone.dart';
import '../services/favorites_store.dart';
import '../widgets/auth_message.dart';
import '../widgets/fretboard.dart';

/// Chords page: the complete library (every quality x all 12 roots, from the
/// generated chord_library), grouped into category menus, with live search,
/// root-note filter, real plucked-string audio (Strum/Arpeggio/per-tile), and
/// bookmarks that persist across restarts via FavoritesStore.
class ChordScreen extends StatefulWidget {
  const ChordScreen({super.key});
  @override
  State<ChordScreen> createState() => _ChordScreenState();
}

class _ChordScreenState extends State<ChordScreen> {
  // 'All' and 'Saved' come first, then the real category menus.
  static const _categories = ['All', 'Saved', ...kChordGroups];

  final _searchCtrl = TextEditingController();
  var _selectedCategory = 0;
  var _selectedRoot = -1; // -1 = any root, else pitch class 0..11.
  ChordDef? _hero;
  Set<String> _favs = {};

  @override
  void initState() {
    super.initState();
    _hero = _firstOf(kAllChords);
    FavoritesStore.instance.load().then((set) {
      if (mounted) setState(() => _favs = set);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- filtering

  bool _matchSearch(ChordDef c, String q) {
    if (q.isEmpty) return true;
    if (c.name.toLowerCase().contains(q)) return true;
    if (c.root.toLowerCase().contains(q)) return true;
    if (c.notes.toLowerCase().contains(q)) return true;
    if (c.group.toLowerCase().contains(q)) return true;
    if (c.suffix.toLowerCase().contains(q)) return true;
    // Allow searching a root by any spelling, e.g. "C#" or "Db".
    for (final e in kNoteAliases.entries) {
      if (e.key.toLowerCase().startsWith(q) &&
          e.value == c.rootPc &&
          c.name.toLowerCase().startsWith(e.key.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  List<ChordDef> get _visible {
    final q = _searchCtrl.text.trim().toLowerCase();
    final cat = _categories[_selectedCategory];
    return kAllChords.where((c) {
      if (_selectedRoot >= 0 && c.rootPc != _selectedRoot) return false;
      if (cat == 'Saved') {
        if (!_favs.contains(c.name)) return false;
      } else if (cat != 'All' && c.group != cat) {
        return false;
      }
      return _matchSearch(c, q);
    }).toList();
  }

  ChordDef? _firstOf(List<ChordDef> list) => list.isEmpty ? null : list.first;

  void _resetHeroTo(List<ChordDef> list) {
    _hero = _firstOf(list);
  }

  // ---------------------------------------------------------------- actions

  Future<void> _play(Future<void> Function(List<double>) play, ChordDef c) async {
    if (!referenceToneSupported) {
      if (mounted) {
        showAuthMessage(context, 'Audio needs a browser for now.', error: false);
      }
      return;
    }
    try {
      await play(c.freqs);
    } catch (_) {
      if (mounted) showAuthMessage(context, 'Could not play chord.', error: false);
    }
  }

  Future<void> _toggleFav(ChordDef c) async {
    final nowSaved = await FavoritesStore.instance.toggle(c.name);
    final set = await FavoritesStore.instance.load();
    if (mounted) {
      setState(() => _favs = set);
      showAuthMessage(
        context,
        nowSaved ? 'Saved ${c.name}' : 'Removed ${c.name}',
        error: false,
      );
    }
  }

  void _select(ChordDef c) => setState(() => _hero = c);

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final cat = _categories[_selectedCategory];
    // Flat list for a chosen category / search; grouped by menu when "All".
    final grouped = cat == 'All' && _searchCtrl.text.trim().isEmpty && _selectedRoot < 0;
    final hero = _hero ?? _firstOf(visible);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            const SizedBox(height: 16),
            _search(),
            const SizedBox(height: 10),
            _categoryChips(),
            const SizedBox(height: 10),
            _rootChips(),
            const SizedBox(height: 16),
            _countRow(visible.length),
            const SizedBox(height: 12),
            if (visible.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                    child: Text('No chords match your filters.',
                        style: TextStyle(color: AppColors.onSurfaceVariant))),
              )
            else ...[
              if (hero != null) _heroCard(hero),
              const SizedBox(height: 20),
              if (grouped)
                ..._groupedSections(visible)
              else
                _tileGrid(visible),
            ],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- widgets

  Widget _header() {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.music_note, size: 14, color: AppColors.onSurface),
          ),
          const SizedBox(width: 10),
          const Text('Rig Music',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: AppColors.onSurface)),
          const Spacer(),
          // Working "Saved chords" button (was a dead bookmark icon).
          IconButton(
            onPressed: _openSavedSheet,
            tooltip: 'Saved chords',
            icon: Icon(
              _favs.isEmpty ? Icons.bookmark_border : Icons.bookmark,
              size: 19,
              color: _favs.isEmpty ? AppColors.onSurfaceVariant : AppColors.tertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _search() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 18, color: AppColors.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() => _resetHeroTo(_visible)),
              style: const TextStyle(fontSize: 12, color: AppColors.onSurface),
              decoration: const InputDecoration(
                hintText: 'Search 324 chords, e.g. Cmaj7, Bb, sus4, dim',
                hintStyle: TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant),
                border: InputBorder.none,
              ),
            ),
          ),
          if (_searchCtrl.text.isNotEmpty)
            GestureDetector(
              onTap: () => setState(() {
                _searchCtrl.clear();
                _resetHeroTo(_visible);
              }),
              child: const Icon(Icons.close, size: 16, color: AppColors.onSurfaceVariant),
            ),
        ],
      ),
    );
  }

  Widget _categoryChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(_categories.length, (i) {
          final active = i == _selectedCategory;
          final label = _categories[i];
          final showSavedCount = label == 'Saved' && _favs.isNotEmpty;
          return Padding(
            padding: EdgeInsets.only(right: i == _categories.length - 1 ? 0 : 8),
            child: GestureDetector(
              onTap: () => setState(() {
                _selectedCategory = i;
                _resetHeroTo(_visible);
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.tertiary.withValues(alpha: 0.15)
                      : AppColors.surfaceContainerLow.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: active
                          ? AppColors.tertiary.withValues(alpha: 0.3)
                          : AppColors.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Text(showSavedCount ? 'Saved (${_favs.length})' : label,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: active ? AppColors.tertiary : AppColors.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _rootChips() {
    final roots = <String>['Any', ...kNoteNames];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List.generate(roots.length, (i) {
          final pc = i - 1; // -1 = Any, else 0..11
          final active = _selectedRoot == pc;
          return Padding(
            padding: EdgeInsets.only(right: i == roots.length - 1 ? 0 : 6),
            child: GestureDetector(
              onTap: () => setState(() {
                _selectedRoot = pc;
                _resetHeroTo(_visible);
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.accent.withValues(alpha: 0.15)
                      : AppColors.surfaceContainerLow.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: active
                          ? AppColors.accent.withValues(alpha: 0.4)
                          : AppColors.outlineVariant.withValues(alpha: 0.25)),
                ),
                child: Text(roots[i],
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: active ? AppColors.accent : AppColors.onSurfaceVariant)),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _countRow(int count) {
    final cat = _categories[_selectedCategory];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(cat == 'All' ? 'ALL CHORDS' : cat.toUpperCase(),
            style: const TextStyle(fontSize: 12, letterSpacing: 1.0, color: AppColors.onSurfaceVariant)),
        Text('$count', style: const TextStyle(fontSize: 11, color: AppColors.tertiary)),
      ],
    );
  }

  Widget _heroCard(ChordDef hero) {
    final isFav = _favs.contains(hero.name);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(hero.name,
                              style: const TextStyle(
                                  fontSize: 30, fontWeight: FontWeight.w300, color: AppColors.onSurface)),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.tertiary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('ROOT ${hero.root}',
                              style: const TextStyle(
                                  fontSize: 11, letterSpacing: 0.8, color: AppColors.tertiary)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('${hero.notes} · ${hero.group} · Standard Tuning',
                        style: const TextStyle(fontSize: 12, color: AppColors.onSurfaceVariant)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => _toggleFav(hero),
                child: Icon(isFav ? Icons.bookmark : Icons.bookmark_border,
                    size: 20, color: isFav ? AppColors.tertiary : AppColors.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Fretboard(
            frets: hero.frets,
            fingers: hero.fingers,
            rootIndex: hero.rootIndex,
            startFret: hero.startFret,
            barreFret: hero.barreFret,
            barreFrom: hero.barreFrom,
            barreTo: hero.barreTo,
            height: 170,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _previewButton(Icons.music_note, 'Strum', true,
                    () => _play(playStrum, hero)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _previewButton(Icons.graphic_eq, 'Arpeggio', false,
                    () => _play(playArpeggio, hero)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _previewButton(IconData icon, String label, bool primary, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: primary
              ? AppColors.tertiary.withValues(alpha: 0.15)
              : AppColors.surfaceContainer.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: primary
                  ? AppColors.tertiary.withValues(alpha: 0.3)
                  : AppColors.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: primary ? AppColors.tertiary : AppColors.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: primary ? AppColors.tertiary : AppColors.onSurface)),
          ],
        ),
      ),
    );
  }

  // Sections in the canonical menu order, each a grid of tiles.
  List<Widget> _groupedSections(List<ChordDef> visible) {
    final byGroup = <String, List<ChordDef>>{};
    for (final c in visible) {
      byGroup.putIfAbsent(c.group, () => []).add(c);
    }
    final out = <Widget>[];
    for (final g in kChordGroups) {
      final list = byGroup[g];
      if (list == null || list.isEmpty) continue;
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(g.toUpperCase(),
                style: const TextStyle(fontSize: 12, letterSpacing: 1.0, color: AppColors.onSurfaceVariant)),
            Text('${list.length}', style: const TextStyle(fontSize: 11, color: AppColors.tertiary)),
          ],
        ),
      ));
      out.add(_tileGrid(list));
      out.add(const SizedBox(height: 12));
    }
    return out;
  }

  Widget _tileGrid(List<ChordDef> list) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.5,
      children: list.map(_tile).toList(),
    );
  }

  Widget _tile(ChordDef c) {
    final selected = _hero?.name == c.name;
    final isFav = _favs.contains(c.name);
    return GestureDetector(
      onTap: () => _select(c),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.tertiary.withValues(alpha: 0.08)
              : AppColors.surfaceContainerLow.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected
                  ? AppColors.tertiary.withValues(alpha: 0.4)
                  : AppColors.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                    child: Text(c.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15, color: AppColors.onSurface))),
                GestureDetector(
                  onTap: () => _toggleFav(c),
                  child: Icon(isFav ? Icons.bookmark : Icons.bookmark_border,
                      size: 15, color: isFav ? AppColors.tertiary : AppColors.onSurfaceVariant),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _fretRow(c),
                GestureDetector(
                  onTap: () => _play(playStrum, c),
                  child: const Icon(Icons.play_arrow_rounded,
                      size: 20, color: AppColors.tertiary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _fretRow(ChordDef c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: c.frets.map((f) {
          final label = f < 0 ? 'x' : (f == 0 ? '0' : '$f');
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: f > 0 ? AppColors.tertiary : AppColors.onSurfaceVariant)),
          );
        }).toList(),
      ),
    );
  }

  // ---------------------------------------------------------------- saved sheet

  void _openSavedSheet() {
    final saved = kAllChords.where((c) => _favs.contains(c.name)).toList();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Saved chords',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.onSurface)),
                  Text('${saved.length}',
                      style: const TextStyle(fontSize: 12, color: AppColors.tertiary)),
                ],
              ),
              const SizedBox(height: 12),
              if (saved.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                      child: Text('Tap the bookmark on any chord to save it here.',
                          style: TextStyle(color: AppColors.onSurfaceVariant))),
                )
              else
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.5),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: saved.length,
                    itemBuilder: (ctx2, i) {
                      final c = saved[i];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.music_note,
                            size: 18, color: AppColors.onSurfaceVariant),
                        title: Text(c.name,
                            style: const TextStyle(fontSize: 15, color: AppColors.onSurface)),
                        subtitle: Text(c.notes,
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.onSurfaceVariant)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () => _play(playStrum, c),
                              icon: const Icon(Icons.play_arrow_rounded,
                                  size: 20, color: AppColors.tertiary),
                            ),
                            IconButton(
                              onPressed: () async {
                                await _toggleFav(c);
                                if (ctx.mounted) Navigator.of(ctx).pop();
                              },
                              icon: const Icon(Icons.bookmark,
                                  size: 18, color: AppColors.tertiary),
                            ),
                          ],
                        ),
                        onTap: () {
                          _select(c);
                          Navigator.of(ctx).pop();
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
