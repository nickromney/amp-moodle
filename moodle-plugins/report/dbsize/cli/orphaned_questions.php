<?php
define('CLI_SCRIPT', true);

require_once(__DIR__ . '/../../../config.php');
require_once($CFG->libdir . '/clilib.php');

$help = "Database size report - question integrity checks

Options:
  --action=ACTION      questions, answers, archived-answers (default: questions)
  --limit=NUM          Limit number of rows (default: 200)
  --export=PATH        Export CSV to PATH
  -h, --help           Show this help

Examples:
  php report/dbsize/cli/orphaned_questions.php --action=questions --limit=200
  php report/dbsize/cli/orphaned_questions.php --action=answers --limit=200 --export=/tmp/orphaned-answers.csv
  php report/dbsize/cli/orphaned_questions.php --action=archived-answers --limit=200
";

list($options, $unrecognized) = cli_get_params(
    [
        'help' => false,
        'action' => 'questions',
        'limit' => 200,
        'export' => null,
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

$action = (string) $options['action'];
$limit = max(1, min((int) $options['limit'], 5000));
$export = $options['export'] !== null ? (string) $options['export'] : null;

if (!in_array($action, ['questions', 'answers', 'archived-answers'], true)) {
    cli_error('Invalid --action. Use questions, answers, or archived-answers.');
}

if ($action === 'questions') {
    $sql = "SELECT q.id, q.name, q.qtype, q.timecreated
              FROM {question} q
         LEFT JOIN {question_versions} qv ON qv.questionid = q.id
             WHERE qv.id IS NULL
          ORDER BY q.timecreated ASC, q.id ASC";
    $records = $DB->get_records_sql($sql, [], 0, $limit);
    if ($export) {
        $handle = fopen($export, 'w');
        if ($handle === false) {
            cli_error('Unable to open export path: ' . $export);
        }
        fputcsv($handle, ['id', 'name', 'qtype', 'timecreated']);
        foreach ($records as $record) {
            fputcsv($handle, [$record->id, $record->name, $record->qtype, $record->timecreated]);
        }
        fclose($handle);
        mtrace('Exported ' . count($records) . ' questions to ' . $export);
        exit(0);
    }
    foreach ($records as $record) {
        mtrace("{$record->id}\t{$record->qtype}\t{$record->name}\t{$record->timecreated}");
    }
    exit(0);
}

if ($action === 'answers') {
    $sql = "SELECT qa.id, qa.question
              FROM {question_answers} qa
         LEFT JOIN {question} q ON q.id = qa.question
             WHERE q.id IS NULL
          ORDER BY qa.id ASC";
    $records = $DB->get_records_sql($sql, [], 0, $limit);
    if ($export) {
        $handle = fopen($export, 'w');
        if ($handle === false) {
            cli_error('Unable to open export path: ' . $export);
        }
        fputcsv($handle, ['answer_id', 'question_id']);
        foreach ($records as $record) {
            fputcsv($handle, [$record->id, $record->question]);
        }
        fclose($handle);
        mtrace('Exported ' . count($records) . ' answers to ' . $export);
        exit(0);
    }
    foreach ($records as $record) {
        mtrace("{$record->id}\t{$record->question}");
    }
    exit(0);
}

$sql = "SELECT qa.id, qa.question, q.name, q.qtype, qv.status
          FROM {question_answers} qa
          JOIN {question_versions} qv ON qv.questionid = qa.question
          JOIN {question} q ON q.id = qa.question
         WHERE qv.status <> 'ready'
      ORDER BY qv.status ASC, qa.id ASC";
$records = $DB->get_records_sql($sql, [], 0, $limit);
if ($export) {
    $handle = fopen($export, 'w');
    if ($handle === false) {
        cli_error('Unable to open export path: ' . $export);
    }
    fputcsv($handle, ['answer_id', 'question_id', 'question_name', 'question_type', 'status']);
    foreach ($records as $record) {
        fputcsv($handle, [$record->id, $record->question, $record->name, $record->qtype, $record->status]);
    }
    fclose($handle);
    mtrace('Exported ' . count($records) . ' answers to ' . $export);
    exit(0);
}

foreach ($records as $record) {
    mtrace("{$record->id}\t{$record->question}\t{$record->qtype}\t{$record->status}\t{$record->name}");
}
