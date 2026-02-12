<?php
require_once(__DIR__ . '/../../config.php');
require_once($CFG->libdir . '/tablelib.php');
require_once($CFG->libdir . '/csvlib.class.php');

$context = context_system::instance();
require_login();
require_capability('report/dbsize:view', $context);

$limit = optional_param('limit', 20, PARAM_INT);
if ($limit < 1) {
    $limit = 20;
}
$limit = min($limit, 200);

$userlimit = optional_param('userlimit', 100, PARAM_INT);
if ($userlimit < 10) {
    $userlimit = 10;
}
$userlimit = min($userlimit, 500);

$inactivedays = optional_param('inactivedays', 365, PARAM_INT);
if ($inactivedays < 1) {
    $inactivedays = 365;
}
$inactivedays = min($inactivedays, 3650);

$questionlimit = optional_param('questionlimit', 200, PARAM_INT);
if ($questionlimit < 10) {
    $questionlimit = 10;
}
$questionlimit = min($questionlimit, 2000);

$export = optional_param('export', '', PARAM_ALPHANUMEXT);
$export = strtolower($export);

$pageurl = new moodle_url('/report/dbsize/index.php', [
    'limit' => $limit,
    'userlimit' => $userlimit,
    'inactivedays' => $inactivedays,
    'questionlimit' => $questionlimit,
]);
$PAGE->set_url($pageurl);
$PAGE->set_context($context);
$PAGE->set_title(get_string('pluginname', 'report_dbsize'));
$PAGE->set_heading(get_string('pluginname', 'report_dbsize'));
$PAGE->set_pagelayout('report');

function report_dbsize_export_csv(string $filename, array $headers, array $rows): void {
    $csv = new csv_export_writer();
    $csv->set_filename($filename);
    $csv->add_data($headers);
    foreach ($rows as $row) {
        $csv->add_data($row);
    }
    $csv->download_file();
    exit;
}

function report_dbsize_fetch_table_sizes($DB, int $limit): array {
    if ($DB->get_dbfamily() !== 'mysql') {
        return [];
    }
    $sql = "SELECT table_name, table_rows, data_length, index_length
              FROM information_schema.tables
             WHERE table_schema = DATABASE()
          ORDER BY (data_length + index_length) DESC";
    return $DB->get_records_sql($sql, [], 0, $limit);
}

function report_dbsize_fetch_orphaned_users($DB, int $cutoff, int $limit): array {
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
    return $DB->get_records_sql($sql, $params, 0, $limit);
}

function report_dbsize_fetch_orphaned_questions($DB, int $limit): array {
    $sql = "SELECT q.id, q.name, q.qtype, q.timecreated
              FROM {question} q
         LEFT JOIN {question_versions} qv ON qv.questionid = q.id
             WHERE qv.id IS NULL
          ORDER BY q.timecreated ASC, q.id ASC";
    return $DB->get_records_sql($sql, [], 0, $limit);
}

function report_dbsize_fetch_orphaned_answers($DB, int $limit): array {
    $sql = "SELECT qa.id, qa.question
              FROM {question_answers} qa
         LEFT JOIN {question} q ON q.id = qa.question
             WHERE q.id IS NULL
          ORDER BY qa.id ASC";
    return $DB->get_records_sql($sql, [], 0, $limit);
}

function report_dbsize_fetch_archived_answers($DB, int $limit): array {
    $sql = "SELECT qa.id, qa.question, q.name, q.qtype, qv.status
              FROM {question_answers} qa
              JOIN {question_versions} qv ON qv.questionid = qa.question
              JOIN {question} q ON q.id = qa.question
             WHERE qv.status <> 'ready'
          ORDER BY qv.status ASC, qa.id ASC";
    return $DB->get_records_sql($sql, [], 0, $limit);
}

$cutoff = time() - ($inactivedays * DAYSECS);

if ($export !== '') {
    switch ($export) {
        case 'tables':
            if ($DB->get_dbfamily() !== 'mysql') {
                throw new moodle_exception('unsupported_db', 'report_dbsize');
            }
            $records = report_dbsize_fetch_table_sizes($DB, $limit);
            $rows = [];
            foreach ($records as $record) {
                $data = (int) $record->data_length;
                $index = (int) $record->index_length;
                $total = $data + $index;
                $rows[] = [
                    $record->table_name,
                    (int) $record->table_rows,
                    $data,
                    $index,
                    $total,
                ];
            }
            report_dbsize_export_csv(
                'dbsize-tables',
                ['table', 'rows', 'data_bytes', 'index_bytes', 'total_bytes'],
                $rows
            );
            break;
        case 'orphaned_users':
            $records = report_dbsize_fetch_orphaned_users($DB, $cutoff, $userlimit);
            $rows = [];
            foreach ($records as $record) {
                $rows[] = [
                    $record->id,
                    $record->username,
                    $record->email,
                    $record->lastaccess ? userdate($record->lastaccess) : '',
                    $record->timecreated ? userdate($record->timecreated) : '',
                    $record->suspended,
                ];
            }
            report_dbsize_export_csv(
                'dbsize-orphaned-users',
                ['id', 'username', 'email', 'lastaccess', 'timecreated', 'suspended'],
                $rows
            );
            break;
        case 'orphaned_questions':
            $records = report_dbsize_fetch_orphaned_questions($DB, $questionlimit);
            $rows = [];
            foreach ($records as $record) {
                $rows[] = [
                    $record->id,
                    $record->name,
                    $record->qtype,
                    $record->timecreated ? userdate($record->timecreated) : '',
                ];
            }
            report_dbsize_export_csv(
                'dbsize-orphaned-questions',
                ['id', 'name', 'qtype', 'timecreated'],
                $rows
            );
            break;
        case 'orphaned_answers':
            $records = report_dbsize_fetch_orphaned_answers($DB, $questionlimit);
            $rows = [];
            foreach ($records as $record) {
                $rows[] = [
                    $record->id,
                    $record->question,
                ];
            }
            report_dbsize_export_csv(
                'dbsize-orphaned-answers',
                ['answer_id', 'question_id'],
                $rows
            );
            break;
        case 'archived_answers':
            $records = report_dbsize_fetch_archived_answers($DB, $questionlimit);
            $rows = [];
            foreach ($records as $record) {
                $rows[] = [
                    $record->id,
                    $record->question,
                    $record->name,
                    $record->qtype,
                    $record->status,
                ];
            }
            report_dbsize_export_csv(
                'dbsize-archived-answers',
                ['answer_id', 'question_id', 'question_name', 'question_type', 'status'],
                $rows
            );
            break;
        default:
            throw new moodle_exception('invalidparameter');
    }
}

echo $OUTPUT->header();
echo $OUTPUT->heading(get_string('tables_heading', 'report_dbsize'), 3);

$limitoptions = [
    20 => '20',
    50 => '50',
    100 => '100',
    200 => '200',
];
$selector = new single_select($pageurl, 'limit', $limitoptions, $limit);
$selector->set_label(get_string('limit', 'report_dbsize'));
echo $OUTPUT->render($selector);

$exporttablesurl = new moodle_url('/report/dbsize/index.php', [
    'limit' => $limit,
    'userlimit' => $userlimit,
    'inactivedays' => $inactivedays,
    'questionlimit' => $questionlimit,
    'export' => 'tables',
]);
echo html_writer::tag('p', html_writer::link($exporttablesurl, get_string('download_csv', 'report_dbsize')));

$tabledata = [];
if ($DB->get_dbfamily() !== 'mysql') {
    echo $OUTPUT->notification(get_string('unsupported_db', 'report_dbsize'), 'warning');
} else {
    $records = report_dbsize_fetch_table_sizes($DB, $limit);
    foreach ($records as $record) {
        $data = (int) $record->data_length;
        $index = (int) $record->index_length;
        $total = $data + $index;
        $tabledata[] = [
            s($record->table_name),
            format_int((int) $record->table_rows),
            display_size($data),
            display_size($index),
            display_size($total),
        ];
    }
}

if (empty($tabledata)) {
    echo $OUTPUT->notification(get_string('notables', 'report_dbsize'), 'info');
} else {
    $table = new html_table();
    $table->head = [
        get_string('table_name', 'report_dbsize'),
        get_string('table_rows', 'report_dbsize'),
        get_string('data_size', 'report_dbsize'),
        get_string('index_size', 'report_dbsize'),
        get_string('total_size', 'report_dbsize'),
    ];
    $table->data = $tabledata;
    echo html_writer::table($table);
    echo html_writer::tag('p', get_string('rows_approx_note', 'report_dbsize'), ['class' => 'dimmed_text']);
}

echo $OUTPUT->heading(get_string('orphaned_heading', 'report_dbsize'), 3);

$daysoptions = [
    90 => '90',
    180 => '180',
    365 => '365',
    730 => '730',
    1095 => '1095',
    1825 => '1825',
    3650 => '3650',
];
$dayselector = new single_select($pageurl, 'inactivedays', $daysoptions, $inactivedays);
$dayselector->set_label(get_string('inactive_days', 'report_dbsize'));
echo $OUTPUT->render($dayselector);

$userlimitoptions = [
    50 => '50',
    100 => '100',
    200 => '200',
    500 => '500',
];
$userlimitselector = new single_select($pageurl, 'userlimit', $userlimitoptions, $userlimit);
$userlimitselector->set_label(get_string('user_limit', 'report_dbsize'));
echo $OUTPUT->render($userlimitselector);

$exportusersurl = new moodle_url('/report/dbsize/index.php', [
    'limit' => $limit,
    'userlimit' => $userlimit,
    'inactivedays' => $inactivedays,
    'questionlimit' => $questionlimit,
    'export' => 'orphaned_users',
]);
echo html_writer::tag('p', html_writer::link($exportusersurl, get_string('download_csv', 'report_dbsize')));

echo html_writer::tag('p', get_string('orphaned_note', 'report_dbsize', $inactivedays));

$cli_export = "php report/dbsize/cli/orphaned_users.php --days={$inactivedays} --limit={$userlimit} --export=/tmp/orphaned-users.csv";
echo html_writer::tag(
    'p',
    get_string('cli_export', 'report_dbsize') . ' ' . html_writer::tag('code', s($cli_export))
);

$orphans = report_dbsize_fetch_orphaned_users($DB, $cutoff, $userlimit);

$usertable = new html_table();
$usertable->head = [
    get_string('user_id', 'report_dbsize'),
    get_string('username'),
    get_string('email'),
    get_string('last_access', 'report_dbsize'),
    get_string('time_created', 'report_dbsize'),
    get_string('suspended', 'report_dbsize'),
    get_string('cli_command', 'report_dbsize'),
];

foreach ($orphans as $user) {
    $lastaccess = $user->lastaccess ? userdate($user->lastaccess) : get_string('never');
    $timecreated = $user->timecreated ? userdate($user->timecreated) : get_string('never');
    $suspended = $user->suspended ? get_string('yes') : get_string('no');
    $cli = "php report/dbsize/cli/orphaned_users.php --userid={$user->id} --action=suspend";
    $usertable->data[] = [
        $user->id,
        s($user->username),
        s($user->email),
        $lastaccess,
        $timecreated,
        $suspended,
        html_writer::tag('code', s($cli)),
    ];
}

if (empty($usertable->data)) {
    echo $OUTPUT->notification(get_string('no_orphans', 'report_dbsize'), 'info');
} else {
    echo html_writer::table($usertable);
    echo html_writer::tag('p', get_string('cli_note', 'report_dbsize'), ['class' => 'dimmed_text']);
}

echo $OUTPUT->heading(get_string('orphaned_questions_heading', 'report_dbsize'), 3);

$questionlimitoptions = [
    50 => '50',
    100 => '100',
    200 => '200',
    500 => '500',
    1000 => '1000',
    2000 => '2000',
];
$questionlimitselector = new single_select($pageurl, 'questionlimit', $questionlimitoptions, $questionlimit);
$questionlimitselector->set_label(get_string('question_limit', 'report_dbsize'));
echo $OUTPUT->render($questionlimitselector);

$exportquestionsurl = new moodle_url('/report/dbsize/index.php', [
    'limit' => $limit,
    'userlimit' => $userlimit,
    'inactivedays' => $inactivedays,
    'questionlimit' => $questionlimit,
    'export' => 'orphaned_questions',
]);
echo html_writer::tag('p', html_writer::link($exportquestionsurl, get_string('download_csv', 'report_dbsize')));

echo html_writer::tag('p', get_string('orphaned_questions_note', 'report_dbsize'));

$cli_question_export = "php report/dbsize/cli/orphaned_questions.php --action=questions --limit={$questionlimit} --export=/tmp/orphaned-questions.csv";
echo html_writer::tag(
    'p',
    get_string('cli_export', 'report_dbsize') . ' ' . html_writer::tag('code', s($cli_question_export))
);

$orphanedquestions = report_dbsize_fetch_orphaned_questions($DB, $questionlimit);
$questiontable = new html_table();
$questiontable->head = [
    get_string('question_id', 'report_dbsize'),
    get_string('question_name', 'report_dbsize'),
    get_string('question_type', 'report_dbsize'),
    get_string('question_created', 'report_dbsize'),
];

foreach ($orphanedquestions as $question) {
    $questiontable->data[] = [
        $question->id,
        format_string($question->name),
        s($question->qtype),
        $question->timecreated ? userdate($question->timecreated) : get_string('never'),
    ];
}

if (empty($questiontable->data)) {
    echo $OUTPUT->notification(get_string('no_orphaned_questions', 'report_dbsize'), 'info');
} else {
    echo html_writer::table($questiontable);
}

echo $OUTPUT->heading(get_string('orphaned_answers_heading', 'report_dbsize'), 3);

$exportanswersurl = new moodle_url('/report/dbsize/index.php', [
    'limit' => $limit,
    'userlimit' => $userlimit,
    'inactivedays' => $inactivedays,
    'questionlimit' => $questionlimit,
    'export' => 'orphaned_answers',
]);
echo html_writer::tag('p', html_writer::link($exportanswersurl, get_string('download_csv', 'report_dbsize')));

echo html_writer::tag('p', get_string('orphaned_answers_note', 'report_dbsize'));

$cli_answer_export = "php report/dbsize/cli/orphaned_questions.php --action=answers --limit={$questionlimit} --export=/tmp/orphaned-answers.csv";
echo html_writer::tag(
    'p',
    get_string('cli_export', 'report_dbsize') . ' ' . html_writer::tag('code', s($cli_answer_export))
);

$orphanedanswers = report_dbsize_fetch_orphaned_answers($DB, $questionlimit);
$answertable = new html_table();
$answertable->head = [
    get_string('answer_id', 'report_dbsize'),
    get_string('question_id', 'report_dbsize'),
];

foreach ($orphanedanswers as $answer) {
    $answertable->data[] = [
        $answer->id,
        $answer->question,
    ];
}

if (empty($answertable->data)) {
    echo $OUTPUT->notification(get_string('no_orphaned_answers', 'report_dbsize'), 'info');
} else {
    echo html_writer::table($answertable);
}

echo $OUTPUT->heading(get_string('archived_answers_heading', 'report_dbsize'), 3);

$exportarchivedurl = new moodle_url('/report/dbsize/index.php', [
    'limit' => $limit,
    'userlimit' => $userlimit,
    'inactivedays' => $inactivedays,
    'questionlimit' => $questionlimit,
    'export' => 'archived_answers',
]);
echo html_writer::tag('p', html_writer::link($exportarchivedurl, get_string('download_csv', 'report_dbsize')));

echo html_writer::tag('p', get_string('archived_answers_note', 'report_dbsize'));

$cli_archived_export = "php report/dbsize/cli/orphaned_questions.php --action=archived-answers --limit={$questionlimit} --export=/tmp/archived-question-answers.csv";
echo html_writer::tag(
    'p',
    get_string('cli_export', 'report_dbsize') . ' ' . html_writer::tag('code', s($cli_archived_export))
);

$archivedanswers = report_dbsize_fetch_archived_answers($DB, $questionlimit);
$archivedtable = new html_table();
$archivedtable->head = [
    get_string('answer_id', 'report_dbsize'),
    get_string('question_id', 'report_dbsize'),
    get_string('question_name', 'report_dbsize'),
    get_string('question_type', 'report_dbsize'),
    get_string('question_status', 'report_dbsize'),
];

foreach ($archivedanswers as $answer) {
    $archivedtable->data[] = [
        $answer->id,
        $answer->question,
        format_string($answer->name),
        s($answer->qtype),
        s($answer->status),
    ];
}

if (empty($archivedtable->data)) {
    echo $OUTPUT->notification(get_string('no_archived_answers', 'report_dbsize'), 'info');
} else {
    echo html_writer::table($archivedtable);
}

echo $OUTPUT->footer();
