<?php
define('CLI_SCRIPT', true);

require_once(__DIR__ . '/../../../config.php');
require_once($CFG->libdir . '/clilib.php');
require_once($CFG->dirroot . '/user/lib.php');

$help = "Database size report - orphaned users

Options:
  --days=NUM           Inactive days threshold (default: 365)
  --limit=NUM          Limit number of users listed (default: 200)
  --export=PATH        Export CSV to PATH
  --userid=ID          Target user ID for suspend action
  --action=ACTION      list (default) or suspend
  --confirm            Apply suspend action
  -h, --help           Show this help

Examples:
  php report/dbsize/cli/orphaned_users.php --days=365 --limit=200
  php report/dbsize/cli/orphaned_users.php --days=365 --limit=200 --export=/tmp/orphaned-users.csv
  php report/dbsize/cli/orphaned_users.php --userid=123 --action=suspend --confirm
";

list($options, $unrecognized) = cli_get_params(
    [
        'help' => false,
        'days' => 365,
        'limit' => 200,
        'export' => null,
        'userid' => null,
        'action' => 'list',
        'confirm' => false,
    ],
    [
        'h' => 'help',
    ]
);

if (!empty($unrecognized)) {
    cli_error('Unknown options: ' . implode(' ', $unrecognized));
}

if (!empty($options['help'])) {
    echo $help;
    exit(0);
}

$days = max(1, min((int) $options['days'], 3650));
$limit = max(1, min((int) $options['limit'], 5000));
$action = (string) $options['action'];
$userid = $options['userid'] !== null ? (int) $options['userid'] : 0;
$confirm = !empty($options['confirm']);

$cutoff = time() - ($days * DAYSECS);
$params = [
    'adminid' => 1,
    'guestid' => 2,
    'cutoff' => $cutoff,
];

$sql = "SELECT u.id, u.username, u.email, u.lastaccess, u.timecreated, u.suspended
          FROM {user} u
     LEFT JOIN {user_enrolments} ue ON ue.userid = u.id
     LEFT JOIN {role_assignments} ra ON ra.userid = u.id
         WHERE u.deleted = 0
           AND u.id <> :adminid
           AND u.id <> :guestid
           AND ue.id IS NULL
           AND ra.id IS NULL
           AND (u.lastaccess = 0 OR u.lastaccess < :cutoff)
      ORDER BY u.lastaccess ASC, u.timecreated ASC";

if ($action === 'suspend') {
    if ($userid === 0) {
        cli_error('Missing --userid for suspend action');
    }

    if ($userid === 1 || $userid === 2) {
        cli_error('Refusing to suspend admin or guest user');
    }

    $user = $DB->get_record('user', ['id' => $userid, 'deleted' => 0], '*', MUST_EXIST);
    if (!$confirm) {
        mtrace("Dry-run: would suspend user {$user->id} ({$user->username}). Add --confirm to apply.");
        exit(0);
    }

    $user->suspended = 1;
    user_update_user($user, false);
    mtrace("Suspended user {$user->id} ({$user->username}).");
    exit(0);
}

$records = $DB->get_records_sql($sql, $params, 0, $limit);

if (!empty($options['export'])) {
    $path = (string) $options['export'];
    $handle = fopen($path, 'w');
    if ($handle === false) {
        cli_error('Unable to open export path: ' . $path);
    }
    fputcsv($handle, ['id', 'username', 'email', 'lastaccess', 'timecreated', 'suspended']);
    foreach ($records as $record) {
        fputcsv($handle, [
            $record->id,
            $record->username,
            $record->email,
            $record->lastaccess,
            $record->timecreated,
            $record->suspended,
        ]);
    }
    fclose($handle);
    mtrace('Exported ' . count($records) . ' users to ' . $path);
    exit(0);
}

foreach ($records as $record) {
    $lastaccess = $record->lastaccess ? userdate($record->lastaccess) : get_string('never');
    $timecreated = $record->timecreated ? userdate($record->timecreated) : get_string('never');
    $suspended = $record->suspended ? get_string('yes') : get_string('no');
    mtrace("{$record->id}\t{$record->username}\t{$record->email}\t{$lastaccess}\t{$timecreated}\t{$suspended}");
}
