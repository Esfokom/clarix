import 'package:clarix/src/features/reader_diagnostics/presentation/instrumented_pdfrx_screen.dart';
import 'package:clarix/src/features/reader_diagnostics/presentation/pointer_trackpad_lab_screen.dart';
import 'package:clarix/src/features/reader_diagnostics/presentation/stock_pdfrx_screen.dart';
import 'package:clarix/src/features/workspace/presentation/screens/workspace_screen.dart';
import 'package:flutter/material.dart';

class ReaderDiagnosticsHub extends StatelessWidget {
  const ReaderDiagnosticsHub({this.workspaceBuilder, super.key});

  final WidgetBuilder? workspaceBuilder;

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E141B),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final bool twoColumns = constraints.maxWidth >= 720;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Reader diagnostics',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Choose an isolated reader scenario to compare input behavior before returning to the workspace.',
                        style: TextStyle(
                          color: Color(0xFFABB8C7),
                          fontSize: 16,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Expanded(
                        child: GridView.count(
                          crossAxisCount: twoColumns ? 2 : 1,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          mainAxisExtent: 224,
                          children: <Widget>[
                            _DestinationCard(
                              key: const Key('open-stock-pdfrx'),
                              icon: Icons.picture_as_pdf_outlined,
                              eyebrow: 'CONTROL',
                              title: 'Stock pdfrx viewer',
                              description:
                                  'Run the unmodified pdfrx viewer as the comparison baseline.',
                              onTap: () => _open(
                                context,
                                const StockPdfrxScreen(),
                              ),
                            ),
                            _DestinationCard(
                              key: const Key('open-instrumented-pdfrx'),
                              icon: Icons.analytics_outlined,
                              eyebrow: 'OBSERVATION CASE',
                              title: 'Instrumented pdfrx viewer',
                              description:
                                  'Inspect viewer, gesture, and pointer observations alongside pdfrx.',
                              onTap: () => _open(
                                context,
                                const InstrumentedPdfrxScreen(),
                              ),
                            ),
                            _DestinationCard(
                              key: const Key('open-pointer-lab'),
                              icon: Icons.touch_app_outlined,
                              eyebrow: 'FLUTTER-INPUT ISOLATION',
                              title: 'Pointer / trackpad lab',
                              description:
                                  'Exercise raw Flutter pointer and scale input without a PDF viewer.',
                              onTap: () => _open(
                                context,
                                const PointerTrackpadLabScreen(),
                              ),
                            ),
                            _DestinationCard(
                              key: const Key('open-workspace'),
                              icon: Icons.space_dashboard_outlined,
                              eyebrow: 'APPLICATION',
                              title: 'Open workspace',
                              description:
                                  'Leave diagnostics and continue in the normal Clarix workspace.',
                              onTap: () {
                                final WidgetBuilder builder =
                                    workspaceBuilder ??
                                    ((_) => const WorkspaceScreen());
                                _open(context, builder(context));
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({
    required this.icon,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String eyebrow;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      color: const Color(0xFF17212C),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF2B3A49)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF24384B),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(icon, color: const Color(0xFF8FD3FF)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      eyebrow,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF8FD3FF),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFBBC7D4),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward, color: Color(0xFF8FD3FF)),
            ],
          ),
        ),
      ),
    );
  }
}
