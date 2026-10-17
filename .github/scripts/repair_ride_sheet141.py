from pathlib import Path

p = Path('lib/video_style_home.dart')
s = p.read_text()
before = """                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, bounds) => SingleChildScrollView(
                      reverse: true,
                      physics: const ClampingScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: bounds.maxHeight),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            AnimatedSize(
                              alignment: Alignment.bottomCenter,
                              duration: const Duration(milliseconds: 240),
                              curve: Curves.easeInOutCubic,
                              child: _buildPassengerBottomPanel(null, data),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),"""
after = """                Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * .84,
                    ),
                    child: SingleChildScrollView(
                      primary: false,
                      physics: const ClampingScrollPhysics(),
                      child: _buildPassengerBottomPanel(null, data),
                    ),
                  ),
                ),"""
if s.count(before) != 1:
    raise SystemExit('route layout pattern changed')
p.write_text(s.replace(before, after))
