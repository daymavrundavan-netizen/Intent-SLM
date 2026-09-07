import 'package:flutter/material.dart';

import 'action_router.dart';
import 'device_action_page.dart';

class DeviceHubPage extends StatelessWidget {
  DeviceHubPage({super.key});

  final ActionRouter _router = ActionRouter();

  void _run(BuildContext context, String command) {
    final resolved = _router.route(command);

    if (resolved == null) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DeviceActionPage(command: resolved)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 30),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            Row(
              children: [
                Container(
                  width: 52,
                  height: 52,

                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(17),
                  ),

                  child: Icon(Icons.devices_rounded, color: scheme.primary),
                ),

                const SizedBox(width: 14),

                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Device Hub',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text('Local Android controls'),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(18),

              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(22),
              ),

              child: const Row(
                children: [
                  Icon(Icons.security_rounded),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'These actions are separated from the competition SLM and execute locally through Android.',
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            const Text(
              'Quick actions',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),

            const SizedBox(height: 14),

            GridView.count(
              shrinkWrap: true,

              physics: const NeverScrollableScrollPhysics(),

              crossAxisCount: 2,

              mainAxisSpacing: 12,

              crossAxisSpacing: 12,

              childAspectRatio: 1.08,

              children: [
                _DeviceTile(
                  icon: Icons.camera_alt_rounded,
                  title: 'Camera',
                  subtitle: 'Open camera',
                  onTap: () => _run(context, 'open camera'),
                ),

                _DeviceTile(
                  icon: Icons.calculate_rounded,
                  title: 'Calculator',
                  subtitle: 'Launch calculator',
                  onTap: () => _run(context, 'open calculator'),
                ),

                _DeviceTile(
                  icon: Icons.flashlight_on_rounded,
                  title: 'Torch On',
                  subtitle: 'Enable flashlight',
                  onTap: () => _run(context, 'turn on the flashlight'),
                ),

                _DeviceTile(
                  icon: Icons.flashlight_off_rounded,
                  title: 'Torch Off',
                  subtitle: 'Disable flashlight',
                  onTap: () => _run(context, 'turn off the flashlight'),
                ),

                _DeviceTile(
                  icon: Icons.language_rounded,
                  title: 'Browser',
                  subtitle: 'Open browser',
                  onTap: () => _run(context, 'open browser'),
                ),
              ],
            ),

            const SizedBox(height: 28),

            const Divider(),

            const SizedBox(height: 18),

            const Text(
              'Architecture',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
            ),

            const SizedBox(height: 12),

            const _PipelineItem(
              number: '1',
              title: 'Command Router',
              description: 'Detects explicit device-control commands.',
            ),

            const _PipelineItem(
              number: '2',
              title: 'Action Dispatcher',
              description: 'Converts structured commands into native calls.',
            ),

            const _PipelineItem(
              number: '3',
              title: 'Android',
              description: 'Executes camera, flashlight and app actions.',
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final IconData icon;

  final String title;

  final String subtitle;

  final VoidCallback onTap;

  const _DeviceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,

      clipBehavior: Clip.antiAlias,

      child: InkWell(
        onTap: onTap,

        child: Padding(
          padding: const EdgeInsets.all(18),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Container(
                width: 48,
                height: 48,

                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),

                child: Icon(icon, color: scheme.primary),
              ),

              const Spacer(),

              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),

              const SizedBox(height: 3),

              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _PipelineItem extends StatelessWidget {
  final String number;

  final String title;

  final String description;

  const _PipelineItem({
    required this.number,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),

      child: Row(
        children: [
          CircleAvatar(child: Text(number)),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,

              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),

                Text(description),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
