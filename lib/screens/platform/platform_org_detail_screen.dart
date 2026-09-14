import 'package:flutter/material.dart';

import '../../data/honeychain_store.dart';
import '../../services/platform_api_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_label.dart';
import '../../widgets/status_pill.dart';

/// Platform Oversight -> Organization detail.
///
/// Governs ONE FPO: lifecycle (activate / suspend / deactivate), bootstrapping
/// its first admin via invite, and membership (assign beekeepers, list
/// members/beekeepers, suspend / reinstate / revoke). Every action is a
/// verified backend call; statuses always come back from the server.
class PlatformOrgDetailScreen extends StatefulWidget {
  const PlatformOrgDetailScreen({super.key, required this.org});

  final PlatformOrganization org;

  @override
  State<PlatformOrgDetailScreen> createState() => _PlatformOrgDetailScreenState();
}

class _PlatformOrgDetailScreenState extends State<PlatformOrgDetailScreen> {
  late PlatformOrganization _org;
  List<PlatformMember>? _members;
  List<PlatformBeekeeper>? _beekeepers;
  List<PlatformAdminInvite> _invites = [];
  String? _error;
  bool _busy = false;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _org = widget.org;
    _load();
  }

  Future<void> _load() async {
    final store = HoneyChainStore.instance;
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        store.platformApi.listMembers(_org.organizationKey),
        store.platformApi.listBeekeepers(orgKey: _org.organizationKey),
      ]);
      if (!mounted) return;
      setState(() {
        _members = results[0] as List<PlatformMember>;
        _beekeepers = results[1] as List<PlatformBeekeeper>;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _lifecycle(String action, String confirmLabel) async {
    final store = HoneyChainStore.instance;
    final confirmed = await _confirm(
      title: '$confirmLabel ${_org.name}?',
      message: 'The backend will update this organization to the new status.',
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final updated = await store.platformApi
          .setOrganizationStatus(_org.organizationKey, action);
      if (!mounted) return;
      setState(() => _org = updated);
      _snack('${_org.name} is now ${_org.status}');
    } on Exception catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _inviteAdmin() async {
    final store = HoneyChainStore.instance;
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) => const _InviteAdminDialog(),
    );
    if (result == null) return;
    final (email, role) = result;
    setState(() => _busy = true);
    try {
      final invite = await store.platformApi.inviteAdmin(
        orgKey: _org.organizationKey,
        email: email,
        role: role,
      );
      if (!mounted) return;
      setState(() => _invites = [invite, ..._invites]);
      await _showInviteToken(invite);
    } on Exception catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _assignBeekeeper() async {
    final store = HoneyChainStore.instance;
    final candidates = _beekeepers
            ?.where((b) => b.isIndependent || b.orgKey.isEmpty)
            .toList() ??
        [];
    if (candidates.isEmpty) {
      // Pull the full roster so an admin can pick an unassigned producer.
      try {
        final all = await store.platformApi.listBeekeepers();
        if (!mounted) return;
        final chosen = await _pickBeekeeper(all);
        if (chosen == null) return;
        await _doAssign(chosen);
      } on Exception catch (e) {
        if (!mounted) return;
        _snack(e.toString().replaceFirst('Exception: ', ''));
      }
      return;
    }
    final chosen = await _pickBeekeeper(candidates);
    if (chosen == null) return;
    await _doAssign(chosen);
  }

  Future<void> _doAssign(PlatformBeekeeper bee) async {
    setState(() => _busy = true);
    try {
      final res = await HoneyChainStore.instance.platformApi
          .assignBeekeeper(_org.organizationKey, bee.id);
      if (!mounted) return;
      _snack('Assigned ${bee.name.isEmpty ? bee.producerId : bee.name} '
          '(${res['role'] ?? 'member'})');
      await _load();
    } on Exception catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<PlatformBeekeeper?> _pickBeekeeper(List<PlatformBeekeeper> list) async {
    return showModalBottomSheet<PlatformBeekeeper>(
      context: context,
      backgroundColor: AppTheme.bg,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text(
                'Assign beekeeper',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.ink,
                ),
              ),
            ),
            const SizedBox(height: 6),
            for (final bee in list)
              ListTile(
                leading: const Icon(Icons.person_outline,
                    size: 20, color: AppTheme.honeyDark),
                title: Text(
                  bee.name.isEmpty ? bee.producerId : bee.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.ink,
                  ),
                ),
                subtitle: Text(
                  '${bee.producerId} · ${bee.orgName.isEmpty ? 'Unassigned' : bee.orgName}',
                  style: const TextStyle(color: AppTheme.inkFaint, fontSize: 12),
                ),
                onTap: () => Navigator.of(sheetContext).pop(bee),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _memberAction(PlatformMember member, String action) async {
    final label = switch (action) {
      'suspend' => 'Suspend',
      'reinstate' => 'Reinstate',
      _ => 'Revoke',
    };
    final name = member.name.isEmpty ? member.email : member.name;
    final confirmed = await _confirm(
      title: '$label $name?',
      message: 'Membership status is enforced by the backend.',
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await HoneyChainStore.instance.platformApi
          .memberAction(_org.organizationKey, member.id, action);
      if (!mounted) return;
      _snack('$label done');
      await _load();
    } on Exception catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm({required String title, required String message}) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink)),
        content: Text(message,
            style: const TextStyle(fontSize: 13.5, color: AppTheme.inkSoft, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _revokeInvite(PlatformAdminInvite invite) async {
    final confirmed = await _confirm(
      title: 'Revoke invite for ${invite.email}?',
      message: 'The invite code will no longer be usable for registration.',
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await HoneyChainStore.instance.platformApi
          .revokeAdminInvite(_org.organizationKey, invite.id);
      if (!mounted) return;
      setState(() {
        _invites = [
          for (final i in _invites)
            if (i.id == invite.id) i.copyWithStatus('REVOKED') else i,
        ];
      });
      _snack('Invite revoked');
    } on Exception catch (e) {
      if (!mounted) return;
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showInviteToken(PlatformAdminInvite invite) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Invite sent',
            style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${invite.email} (${invite.role}) — ${invite.status}. Share this invite code so they can register as the FPO admin:',
              style: const TextStyle(fontSize: 13.5, color: AppTheme.inkSoft, height: 1.4),
            ),
            const SizedBox(height: 12),
            SelectableText(
              invite.token,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppTheme.honeyDark,
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.honeyDark,
        behavior: SnackBarBehavior.floating,
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppTheme.ink,
        title: const Text('Organization',
            style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          children: [
            _OrgHeaderCard(org: _org),
            const SizedBox(height: 12),
            _LifecycleRow(
              status: _org.status,
              busy: _busy,
              onActivate: () => _lifecycle('activate', 'Activate'),
              onSuspend: () => _lifecycle('suspend', 'Suspend'),
              onDeactivate: () => _lifecycle('deactivate', 'Deactivate'),
            ),
            const SizedBox(height: 18),
            SectionLabel('Bootstrap admin'),
            _AdminInviteCard(
              onInvite: _inviteAdmin,
              invites: _invites,
              onRevoke: _revokeInvite,
              busy: _busy,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(fontSize: 12.5, color: AppTheme.red),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _TabChip(
                    label: 'Members',
                    count: _members?.length ?? 0,
                    selected: _tab == 0,
                    onTap: () => setState(() => _tab = 0),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _TabChip(
                    label: 'Beekeepers',
                    count: _beekeepers?.length ?? 0,
                    selected: _tab == 1,
                    onTap: () => setState(() => _tab = 1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (_tab == 0) ...[
              if (_busy && _members == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Members',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: AppTheme.inkFaint,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _busy ? null : _assignBeekeeper,
                      icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                      label: const Text('Assign beekeeper'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        textStyle: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_members == null || _members!.isEmpty)
                  const _EmptyCard(text: 'No members assigned to this FPO yet.')
                else
                  for (final member in _members!) ...[
                    _MemberCard(
                      member: member,
                      onSuspend: member.isActive
                          ? () => _memberAction(member, 'suspend')
                          : null,
                      onReinstate: member.isSuspended
                          ? () => _memberAction(member, 'reinstate')
                          : null,
                      onRevoke: () => _memberAction(member, 'revoke'),
                    ),
                    const SizedBox(height: 8),
                  ],
              ],
            ] else ...[
              if (_busy && _beekeepers == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                if (_beekeepers == null || _beekeepers!.isEmpty)
                  const _EmptyCard(text: 'No beekeepers in scope for this FPO.')
                else
                  for (final bee in _beekeepers!) ...[
                    _BeekeeperCard(bee: bee),
                    const SizedBox(height: 8),
                  ],
              ],
            ],
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _OrgHeaderCard extends StatelessWidget {
  const _OrgHeaderCard({required this.org});

  final PlatformOrganization org;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (org.status) {
      'ACTIVE' => AppTheme.green,
      'SUSPENDED' => AppTheme.orange,
      'DORMANT' => AppTheme.red,
      _ => AppTheme.grey,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
        boxShadow: const [AppTheme.shadowCard],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  color: AppTheme.honey,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.storefront_outlined,
                    color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      org.organizationKey,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.honeyDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      org.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                      ),
                    ),
                  ],
                ),
              ),
              StatusPill(label: org.status, color: statusColor),
            ],
          ),
          const SizedBox(height: 12),
          if (org.location.isNotEmpty || org.state.isNotEmpty) ...[
            _metaRow(Icons.place_outlined,
                [org.district, org.state, org.country].where((s) => s.isNotEmpty).join(' · ')),
            if (org.contactEmail.isNotEmpty)
              _metaRow(Icons.mail_outline, org.contactEmail),
            if (org.contactPhone.isNotEmpty)
              _metaRow(Icons.phone_outlined, org.contactPhone),
          ],
        ],
      ),
    );
  }

  Widget _metaRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppTheme.inkFaint),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: AppTheme.inkFaint),
            ),
          ),
        ],
      ),
    );
  }
}

class _LifecycleRow extends StatelessWidget {
  const _LifecycleRow({
    required this.status,
    required this.busy,
    required this.onActivate,
    required this.onSuspend,
    required this.onDeactivate,
  });

  final String status;
  final bool busy;
  final VoidCallback onActivate;
  final VoidCallback onSuspend;
  final VoidCallback onDeactivate;

  @override
  Widget build(BuildContext context) {
    final active = status == 'ACTIVE';
    final pending = status == 'PENDING';
    final dormant = status == 'DORMANT';
    final suspended = status == 'SUSPENDED';
    return Row(
      children: [
        if (active || pending || suspended || dormant)
          Expanded(
            child: _ActionButton(
              icon: Icons.play_circle_outline,
              label: 'Activate',
              onTap: busy ? null : onActivate,
              busy: busy && active == false && status == 'PENDING',
            ),
          ),
        if (active) ...[
          const SizedBox(width: 8),
          Expanded(
            child: _ActionButton(
              icon: Icons.pause_circle_outline,
              label: 'Suspend',
              onTap: busy ? null : onSuspend,
              busy: false,
            ),
          ),
        ],
        if (active || suspended) ...[
          const SizedBox(width: 8),
          Expanded(
            child: _ActionButton(
              icon: Icons.cancel_outlined,
              label: 'Deactivate',
              onTap: busy ? null : onDeactivate,
              busy: false,
            ),
          ),
        ],
        if (pending && !active)
          Expanded(
            child: _ActionButton(
              icon: Icons.pending_outlined,
              label: 'Pending',
              onTap: null,
              busy: false,
            ),
          ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.busy,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      icon: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 12.5)),
    );
  }
}

class _AdminInviteCard extends StatelessWidget {
  const _AdminInviteCard({
    required this.onInvite,
    required this.invites,
    required this.onRevoke,
    required this.busy,
  });

  final VoidCallback onInvite;
  final List<PlatformAdminInvite> invites;
  final ValueChanged<PlatformAdminInvite> onRevoke;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardWarm,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.mail_outline, size: 18, color: AppTheme.honeyDark),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Invite the FPO admin',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
              ),
              IconButton(
                onPressed: busy ? null : onInvite,
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_rounded, size: 22, color: AppTheme.honeyDark),
                tooltip: 'Invite admin',
              ),
            ],
          ),
          const Text(
            'The invite code lets them register with the fpo role against this organization.',
            style: TextStyle(fontSize: 12, color: AppTheme.inkFaint, height: 1.35),
          ),
          if (invites.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final invite in invites) ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${invite.email} · ${invite.status}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => onRevoke(invite),
                    icon: const Icon(Icons.undo_rounded, size: 18, color: AppTheme.red),
                    tooltip: 'Revoke invite',
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? AppTheme.honey.withValues(alpha: 0.16) : AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.honeyGold : AppTheme.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          '$label ($count)',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: selected ? AppTheme.ink : AppTheme.inkSoft,
          ),
        ),
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.onSuspend,
    required this.onReinstate,
    required this.onRevoke,
  });

  final PlatformMember member;
  final VoidCallback? onSuspend;
  final VoidCallback? onReinstate;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final statusColor =
        member.isActive ? AppTheme.green : (member.isSuspended ? AppTheme.orange : AppTheme.grey);
    final name = member.name.isEmpty ? member.email : member.name;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline, size: 20, color: AppTheme.honeyDark),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.ink,
                      ),
                    ),
                    Text(
                      '${member.role} · ${member.email}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.inkFaint),
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: member.status,
                color: statusColor,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (onSuspend != null)
                TextButton.icon(
                  onPressed: onSuspend,
                  icon: const Icon(Icons.pause_circle_outline, size: 16),
                  label: const Text('Suspend'),
                  style: TextButton.styleFrom(minimumSize: const Size(0, 32)),
                ),
              if (onReinstate != null) ...[
                TextButton.icon(
                  onPressed: onReinstate,
                  icon: const Icon(Icons.play_circle_outline, size: 16),
                  label: const Text('Reinstate'),
                  style: TextButton.styleFrom(minimumSize: const Size(0, 32)),
                ),
                const SizedBox(width: 4),
              ],
              const Spacer(),
              TextButton.icon(
                onPressed: onRevoke,
                icon: const Icon(Icons.person_remove_outlined, size: 16),
                label: const Text('Revoke'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  foregroundColor: AppTheme.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BeekeeperCard extends StatelessWidget {
  const _BeekeeperCard({required this.bee});

  final PlatformBeekeeper bee;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.hive_outlined, size: 20, color: AppTheme.honeyDark),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bee.name.isEmpty ? bee.producerId : bee.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.ink,
                  ),
                ),
                Text(
                  '${bee.producerId} · ${bee.orgName.isEmpty ? 'Unassigned' : bee.orgName}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.inkFaint),
                ),
              ],
            ),
          ),
          if (!bee.isIndependent)
            const StatusPill(label: StatusPill.healthy, color: AppTheme.green)
          else
            const StatusPill(label: 'Independent', color: AppTheme.grey),
        ],
      ),
    );
  }
}

class _InviteAdminDialog extends StatefulWidget {
  const _InviteAdminDialog();

  @override
  State<_InviteAdminDialog> createState() => _InviteAdminDialogState();
}

class _InviteAdminDialogState extends State<_InviteAdminDialog> {
  final _email = TextEditingController();
  String _role = 'fpo';

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Invite FPO admin',
          style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.ink)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Admin email',
              hintText: 'admin@fpo.example.in',
              prefixIcon: Icon(Icons.mail_outline, size: 20),
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: _role,
            decoration: const InputDecoration(labelText: 'Role'),
            items: const [
              DropdownMenuItem(value: 'fpo', child: Text('FPO admin (fpo)')),
            ],
            onChanged: (v) => setState(() => _role = v ?? 'fpo'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final email = _email.text.trim();
            if (email.isEmpty) return;
            Navigator.of(context).pop((email, _role));
          },
          child: const Text('Send invite'),
        ),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: AppTheme.radiusCard,
        border: Border.all(color: AppTheme.border),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, color: AppTheme.inkSoft),
      ),
    );
  }
}