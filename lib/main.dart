import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

// Free key: https://pixabay.com/api/docs/
const String kPixabayKey = '58130302-16c9654b934330a0f36edc19e';

void main() => runApp(const ViralStudio());

class ViralStudio extends StatelessWidget {
  const ViralStudio({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Viral Studio',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: Colors.pinkAccent,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        home: const Home(),
      );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  final pages = const [EnhanceTab(), VideosTab(), TipsTab()];

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Viral Studio')),
        body: pages[tab],
        bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.auto_fix_high), label: 'Enhance'),
            NavigationDestination(icon: Icon(Icons.hd), label: '4K Videos'),
            NavigationDestination(icon: Icon(Icons.trending_up), label: 'Viral Tips'),
          ],
        ),
      );
}

// ---------------- TAB 1: Video Enhancer ----------------
class EnhanceTab extends StatefulWidget {
  const EnhanceTab({super.key});
  @override
  State<EnhanceTab> createState() => _EnhanceTabState();
}

class _EnhanceTabState extends State<EnhanceTab> {
  File? video;
  bool is4k = false;
  bool busy = false;
  String status = 'Video select karein';

  Future<void> pick() async {
    final x = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (x != null) {
      setState(() {
        video = File(x.path);
        status = 'Video ready';
      });
    }
  }

  Future<void> enhance() async {
    if (video == null) return;
    setState(() {
      busy = true;
      status = 'Enhance ho rahi hai... (4K me time lagta hai)';
    });

    final dir = await getTemporaryDirectory();
    final out = '${dir.path}/enhanced_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final w = is4k ? 2160 : 1080;
    final h = is4k ? 3840 : 1920;

    // Upscale (lanczos) + denoise + sharpen + light color boost, 9:16 for TikTok
    final vf = 'scale=$w:$h:force_original_aspect_ratio=decrease:flags=lanczos,'
        'pad=$w:$h:(ow-iw)/2:(oh-ih)/2,'
        'hqdn3d=1.5:1.5:6:6,unsharp=5:5:0.8,eq=contrast=1.05:saturation=1.1';

    final cmd = '-y -i "${video!.path}" -vf "$vf" '
        '-c:v libx264 -preset veryfast -crf 18 -c:a copy "$out"';

    try {
      final session = await FFmpegKit.execute(cmd);
      final rc = await session.getReturnCode();
      if (ReturnCode.isSuccess(rc)) {
        await Gal.putVideo(out);
        status = 'Done! Gallery me save ho gayi.';
      } else {
        status = 'Error aaya. Dobara try karein.';
      }
    } catch (e) {
      status = 'Error: $e';
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: busy ? null : pick,
              icon: const Icon(Icons.video_library),
              label: const Text('Video chunein'),
            ),
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Full HD 1080p')),
                ButtonSegment(value: true, label: Text('4K')),
              ],
              selected: {is4k},
              onSelectionChanged: busy ? null : (s) => setState(() => is4k = s.first),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: (busy || video == null) ? null : enhance,
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('Enhance karein'),
            ),
            const SizedBox(height: 24),
            if (busy) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Text(status, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            const Text(
              'Note: upscaling quality behtar dikhati hai, asli detail nahi banati. '
              'Original video jitni acchi hogi, result utna acha hoga.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
}

// ---------------- TAB 2: 4K Video Suggestions (Pixabay) ----------------
class VideosTab extends StatefulWidget {
  const VideosTab({super.key});
  @override
  State<VideosTab> createState() => _VideosTabState();
}

class _VideosTabState extends State<VideosTab> {
  final ctrl = TextEditingController(text: 'nature');
  List<Map<String, dynamic>> items = [];
  bool loading = false;

  @override
  void initState() {
    super.initState();
    search();
  }

  Future<void> search() async {
    setState(() => loading = true);
    try {
      final uri = Uri.parse(
          'https://pixabay.com/api/videos/?key=$kPixabayKey&q=${Uri.encodeComponent(ctrl.text)}&per_page=100');
      final res = await http.get(uri);
      final data = jsonDecode(res.body);
      final out = <Map<String, dynamic>>[];
      for (final hit in (data['hits'] as List? ?? [])) {
        final big = hit['videos']?['large'];
        if (big == null) continue;
        final w = (big['width'] ?? 0) as int;
        final h = (big['height'] ?? 0) as int;
        // Keep only real 4K (3840 on the long side)
        if (w < 3840 && h < 3840) continue;
        final t = big['thumbnail'];
        final thumb = (t is String && t.isNotEmpty)
            ? t
            : 'https://i.vimeocdn.com/video/${hit['picture_id']}_640x360.jpg';
        out.add({'thumb': thumb, 'link': big['url'], 'res': '${w}x$h'});
      }
      items = out;
    } catch (_) {
      items = [];
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: ctrl,
              onSubmitted: (_) => search(),
              decoration: InputDecoration(
                hintText: 'Search 4K videos (e.g. city, food, travel)',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: search),
              ),
            ),
          ),
          if (loading) const LinearProgressIndicator(),
          Expanded(
            child: items.isEmpty && !loading
                ? const Center(child: Text('Koi 4K video nahi mili (API key check karein)'))
                : GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2, childAspectRatio: 0.8, crossAxisSpacing: 8, mainAxisSpacing: 8),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final it = items[i];
                      return InkWell(
                        onTap: () => launchUrl(Uri.parse(it['link']), mode: LaunchMode.externalApplication),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(it['thumb'], fit: BoxFit.cover),
                            ),
                            Positioned(
                              left: 6,
                              bottom: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration:
                                    BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                                child: Text('4K  ${it['res']}', style: const TextStyle(fontSize: 11)),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      );
}

// ---------------- TAB 3: Viral Tips (hashtags + hooks) ----------------
class TipsTab extends StatefulWidget {
  const TipsTab({super.key});
  @override
  State<TipsTab> createState() => _TipsTabState();
}

class _TipsTabState extends State<TipsTab> {
  final ctrl = TextEditingController();
  String result = '';

  void generate() {
    final n = ctrl.text.trim().toLowerCase().replaceAll(' ', '');
    if (n.isEmpty) return;
    final tags = ['#fyp', '#foryou', '#viral', '#trending', '#$n', '#${n}tok', '#${n}tips', '#${n}daily'];
    setState(() => result = tags.join(' '));
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: ctrl,
            decoration: const InputDecoration(
                labelText: 'Aapka niche (food, fitness, comedy...)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: generate, child: const Text('Hashtags banayein')),
          if (result.isNotEmpty) ...[
            const SizedBox(height: 12),
            SelectableText(result),
            TextButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: result)),
              icon: const Icon(Icons.copy),
              label: const Text('Copy'),
            ),
          ],
          const Divider(height: 32),
          const Text('Viral hone ke asli tareeqe', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          const Text(
            '• Pehle 2 second me strong hook (sawal ya surprise)\n'
            '• Video 7-15 sec rakhein taake log dobara dekhein\n'
            '• Trending sound use karein (TikTok app me check karein)\n'
            '• Roz ya har doosre din post karein\n'
            '• Raat 7-10 baje ya jab aapki audience active ho\n'
            '• Comments ka jawab video se dein\n'
            '• 3-5 relevant hashtags, 20 nahi',
            style: TextStyle(height: 1.6),
          ),
        ],
      );
}
