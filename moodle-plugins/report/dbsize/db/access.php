<?php
defined('MOODLE_INTERNAL') || die();

$capabilities = [
    'report/dbsize:view' => [
        'captype' => 'read',
        'contextlevel' => CONTEXT_SYSTEM,
        'archetypes' => [
            'manager' => CAP_ALLOW,
        ],
    ],
];
