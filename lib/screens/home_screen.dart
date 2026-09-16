import 'package:flutter/material.dart';

import '../models/job.dart';
import '../services/graph_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/ops_brain_home_button.dart';
import 'graph_canvas_screen.dart';
import 'new_job_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    this.jobs = const [],
    this.repository,
    super.key,
  });

  final List<Job> jobs;
  final GraphRepository? repository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<SavedGraphSummary>> _savedGraphs = _loadGraphs();

  Future<List<SavedGraphSummary>> _loadGraphs() async {
    final repository = widget.repository;
    final saved = repository == null
        ? <SavedGraphSummary>[]
        : await repository.listGraphs();
    final savedIds = saved.map((item) => item.id).toSet();
    return [
      ...saved,
      for (final job in widget.jobs)
        if (!savedIds.contains(job.id))
          SavedGraphSummary(
            id: job.id,
            job: job,
            updatedAt: job.createdDate,
            isPersisted: false,
          ),
    ];
  }

  void _refresh() {
    setState(() {
      _savedGraphs = _loadGraphs();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFC20000),
      appBar: AppBar(
        title: const Text('BugManGraphs'),
        actions: const [OpsBrainHomeButton()],
        centerTitle: false,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(4),
          child: SizedBox(
            height: 4,
            child: ColoredBox(color: Color(0xFFC20000)),
          ),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<List<SavedGraphSummary>>(
          future: _savedGraphs,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return widget.jobs.isEmpty
                  ? const _EmptyJobsState()
                  : const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: TextButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Saved graphs could not be loaded'),
                ),
              );
            }
            final graphs = snapshot.data ?? const <SavedGraphSummary>[];
            if (graphs.isEmpty) return const _EmptyJobsState();
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: graphs.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final graph = graphs[index];
                return _JobCard(
                  job: graph.job,
                  onTap: () => _openGraph(graph),
                  onEdit: graph.isPersisted ? () => _editGraph(graph) : null,
                  onDelete:
                      graph.isPersisted ? () => _deleteGraph(graph) : null,
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFFC20000),
        onPressed: () async {
          await Navigator.of(context).pushNamed(NewJobScreen.routeName);
          if (mounted) _refresh();
        },
        icon: const Icon(Icons.add),
        label: const Text('New Job'),
        shape: const StadiumBorder(
          side: BorderSide(color: AppColors.white, width: 2),
        ),
      ),
    );
  }

  Future<void> _openGraph(SavedGraphSummary summary) async {
    final repository = widget.repository;
    if (repository == null || !summary.isPersisted) {
      await Navigator.of(context).pushNamed(
        GraphCanvasScreen.routeName,
        arguments: summary.job,
      );
    } else {
      final document = await repository.loadGraph(summary.id);
      if (!mounted) return;
      if (document == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved graph could not be opened')),
        );
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => GraphCanvasScreen(
            document: document,
            repository: repository,
          ),
        ),
      );
    }
    if (mounted) _refresh();
  }

  Future<void> _editGraph(SavedGraphSummary summary) async {
    final repository = widget.repository;
    if (repository == null || !summary.isPersisted) return;
    Job? editedJob;
    editedJob = await Navigator.of(context).push<Job>(
      MaterialPageRoute<Job>(
        builder: (context) => NewJobScreen(
          initialJob: summary.job,
          editOnly: true,
          onCreateJob: (job) => editedJob = job,
        ),
      ),
    );
    if (!mounted || editedJob == null) return;
    final document = await repository.loadGraph(summary.id);
    if (document == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved graph could not be updated')),
        );
      }
      return;
    }
    document.updateJob(editedJob!);
    await repository.saveGraph(document);
    document.markClean();
    if (mounted) _refresh();
  }

  Future<void> _deleteGraph(SavedGraphSummary summary) async {
    final repository = widget.repository;
    if (repository == null || !summary.isPersisted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete saved job?'),
        content: Text(
          '${summary.job.displayName} and its saved graph will be removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await repository.deleteGraph(summary.id);
    if (!mounted) return;
    _refresh();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved job deleted')),
    );
  }
}

class _EmptyJobsState extends StatelessWidget {
  const _EmptyJobsState();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 600;
        final horizontalPadding = isCompact ? 16.0 : 32.0;
        final logoExtent = isCompact ? 240.0 : 360.0;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            24,
            horizontalPadding,
            104,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight:
                  (constraints.maxHeight - 128).clamp(0, double.infinity),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    border: Border.all(
                      color: const Color(0xFF7D7D7D),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x3D000000),
                        blurRadius: 24,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(isCompact ? 24 : 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Image.asset(
                          AppAssets.hollomanLogo,
                          key: const ValueKey('holloman-logo'),
                          width: logoExtent,
                          height: logoExtent,
                          fit: BoxFit.contain,
                          semanticLabel: 'Holloman Exterminators logo',
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'No jobs yet',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                color: AppColors.black,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Create a job to start a new structure graph.',
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: AppColors.wolfGrey,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.job,
    required this.onTap,
    this.onEdit,
    this.onDelete,
  });

  final Job job;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final address = job.serviceAddress.trim();
    final chips = <Widget>[
      if (job.pestPacLocationNumber.trim().isNotEmpty)
        _JobChip(
          icon: Icons.location_searching,
          label: 'Location # ${job.pestPacLocationNumber}',
        ),
      if (job.pestPacBillToNumber.trim().isNotEmpty)
        _JobChip(
          icon: Icons.receipt_long_outlined,
          label: 'Bill-To # ${job.pestPacBillToNumber}',
        ),
      if (job.serviceType.trim().isNotEmpty)
        _JobChip(
          icon: Icons.bug_report_outlined,
          label: job.serviceType,
        ),
    ];

    return Card(
      clipBehavior: Clip.antiAlias,
      color: AppColors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Color(0xFF7D7D7D), width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      job.displayName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (onEdit != null || onDelete != null)
                    PopupMenuButton<_JobAction>(
                      key: const ValueKey('job-actions-menu'),
                      tooltip: 'Job actions',
                      icon: const Icon(
                        Icons.more_vert,
                        color: AppColors.black,
                      ),
                      onSelected: (action) {
                        switch (action) {
                          case _JobAction.edit:
                            onEdit?.call();
                          case _JobAction.delete:
                            onDelete?.call();
                        }
                      },
                      itemBuilder: (context) => [
                        if (onEdit != null)
                          const PopupMenuItem(
                            value: _JobAction.edit,
                            child: ListTile(
                              leading: Icon(Icons.edit_outlined),
                              title: Text('Edit job information'),
                            ),
                          ),
                        if (onDelete != null)
                          const PopupMenuItem(
                            value: _JobAction.delete,
                            child: ListTile(
                              leading: Icon(Icons.delete_outline),
                              title: Text('Delete saved job'),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
              if (address.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(address),
              ],
              if (chips.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: chips,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

enum _JobAction { edit, delete }

class _JobChip extends StatelessWidget {
  const _JobChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18),
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}
