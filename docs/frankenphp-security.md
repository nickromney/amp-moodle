# FrankenPHP spike image

The experimental Docker spike pins the FrankenPHP 1.13.2 PHP 8.4.27 Bookworm
multi-platform image by digest. Docker Hub returned this digest for the tag on
2026-10-28. The [FrankenPHP 1.13.2 release notes](https://github.com/php/frankenphp/releases/tag/v1.13.2)
state that its images include the PHP fixes for
[GHSA-w8hw-w9fx-j79w](https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w)
and [GHSA-6wmf-4rv5-p3rp](https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp).

The spike rebuilds its image on each invocation using Docker's layer cache. This
avoids reusing an image built from the former floating base tag. The source pin
and release notes do not independently verify the embedded serving runtime.
A local spike run does not prove the PHP version used by a deployment.
