# Laravel + Artisan Variant

> Console-command-driven Laravel projects. Extends `modules/frameworks/laravel/conventions.md`.
> Use this variant when the primary surface is a CLI / batch / daemon process (data importers,
> reconciliation runners, scheduled jobs, background workers) and the HTTP layer is secondary or
> absent. Common for ETL, ops tooling, and Laravel-as-a-task-runner deployments.

## Command Anatomy

```php
namespace App\Console\Commands;

use Illuminate\Console\Command;

class ReconcileBilling extends Command
{
    protected $signature = 'app:reconcile-billing
                            {--from= : ISO-8601 start date}
                            {--to=   : ISO-8601 end date}
                            {--dry-run : Print actions without writing}';

    protected $description = 'Reconcile billing events against the upstream provider.';

    public function handle(BillingReconciler $reconciler): int
    {
        $window = $this->parseWindow();
        $report = $reconciler->reconcile($window, dryRun: $this->option('dry-run'));

        $this->table(['account', 'delta', 'action'], $report->rows());
        $this->info("Reconciled {$report->count} accounts ({$report->errorCount} errors).");

        return $report->errorCount === 0 ? self::SUCCESS : self::FAILURE;
    }
}
```

Constructor injection works inside `handle()` via the container — never instantiate collaborators with `new` inside `handle()`.

## Long-Running Daemons vs One-Shot Commands

| Pattern | Use case | Lifecycle |
|---|---|---|
| One-shot (`handle()` returns) | Batch import, nightly reconciliation, ad-hoc maintenance | Process exits when `handle()` returns |
| Daemon (`while (! $this->shouldQuit) { ... }`) | Custom queue worker, polling consumer, long-poll subscriber | Process runs until SIGTERM / `--stop-when-empty` |
| Queue worker (`php artisan queue:work`) | Standard queued jobs | Built-in, restart on memory threshold via `--max-memory=128` |

Prefer queue jobs over hand-rolled daemons when possible — Laravel's queue worker handles signals, memory limits, supervisor restarts, and Horizon dashboards out of the box.

## Signal Handling

Long-running commands must trap SIGTERM cleanly so supervisor / k8s can roll them without losing in-flight work:

```php
public function handle(): int
{
    pcntl_async_signals(true);
    $this->trap([SIGTERM, SIGINT], fn () => $this->shouldQuit = true);

    while (! $this->shouldQuit) {
        $batch = $this->fetchBatch();
        if ($batch->isEmpty()) {
            sleep(1);
            continue;
        }
        $this->process($batch);
    }

    $this->info('Drained queue, exiting cleanly.');
    return self::SUCCESS;
}
```

`Command::trap` (Laravel 9+) is the supported signal hook. Avoid `pcntl_signal` directly — it bypasses the framework's handler chain.

## `--isolated` for Mutual Exclusion

Concurrent runs of the same command on the same host (cron + supervisor + ad-hoc) corrupt counters and double-bill. Use `--isolated`:

```bash
php artisan app:reconcile-billing --isolated
```

`--isolated` (Laravel 9+) acquires an atomic cache lock keyed by command name + arguments. Default exit code on lock collision is `0` (silent success); pass `--isolated=1` to exit non-zero so cron logs the conflict.

For multi-host deployments use the schedule's `->onOneServer()` instead — that locks via the cache backend across hosts.

## Scheduling in `routes/console.php` (Laravel 11)

Laravel 11 moved the schedule out of `App\Console\Kernel`:

```php
// routes/console.php
use Illuminate\Support\Facades\Schedule;

Schedule::command('app:reconcile-billing --from=yesterday')
    ->dailyAt('02:00')
    ->onOneServer()
    ->withoutOverlapping(60)         // 60-minute lock window
    ->runInBackground()
    ->emailOutputOnFailure('ops@example.com');

Schedule::command('app:warm-cache')
    ->everyFifteenMinutes()
    ->skip(fn () => app()->isDownForMaintenance());
```

Mandatory cron entry on the host:

```cron
* * * * * cd /var/www/app && php artisan schedule:run >> /dev/null 2>&1
```

## Exit Codes and Output Verbosity

| Constant | Value | Meaning |
|---|---|---|
| `Command::SUCCESS` | 0 | Normal completion |
| `Command::FAILURE` | 1 | Recoverable error — caller may retry |
| `Command::INVALID` | 2 | Bad arguments / pre-condition |

Always `return` an explicit code from `handle()`. `return null` exits 0 silently, hiding failures.

Verbosity propagates from the CLI flag (`-v`, `-vv`, `-vvv`) into output methods:

```php
$this->info('always');             // shown at default verbosity
$this->line('always', 'comment');  // styled as comment
$this->getOutput()->writeln('verbose only', OutputInterface::VERBOSITY_VERBOSE);
$this->getOutput()->writeln('debug only',   OutputInterface::VERBOSITY_DEBUG);
```

Use `$this->withProgressBar($iterable, fn ($item) => ...)` for batch operations — visible in default verbosity, suppressed in non-TTY (cron) runs automatically.

## Custom Stubs

Override the default `make:command` stub to enforce house style (typed return on `handle`, default `--dry-run` flag, structured logging):

```bash
php artisan stub:publish
# edit stubs/console.stub
```

The published stub lives in `stubs/console.stub` and applies to every subsequent `php artisan make:command` invocation.

## Testing Commands

```php
public function test_reconcile_command_reports_zero_errors(): void
{
    $this->artisan('app:reconcile-billing', ['--dry-run' => true])
        ->expectsOutputToContain('Reconciled')
        ->assertExitCode(Command::SUCCESS);
}
```

`assertExitCode`, `expectsQuestion`, `expectsConfirmation`, `expectsTable` cover the common interaction surface. For commands that mutate the DB use the `RefreshDatabase` / `DatabaseTransactions` traits as you would for HTTP feature tests.

## Dos

- Always `return` an explicit `Command::SUCCESS` / `Command::FAILURE` / `Command::INVALID` from `handle()`
- Add a `--dry-run` flag to every command that mutates data; default to dry-run in CI smoke tests
- Use `--isolated` (single host) or `->onOneServer()` (multi-host) for any command that must not run twice concurrently
- Trap SIGTERM/SIGINT in long-running daemons via `Command::trap` and exit cleanly when the flag is set
- Schedule via `routes/console.php` (Laravel 11) — never resurrect `App\Console\Kernel`
- Use `$this->withProgressBar(...)` for batch loops — auto-suppressed in non-TTY environments

## Don'ts

- Don't `return null` from `handle()` — it silently exits 0 and masks failures
- Don't `new` collaborators inside `handle()` — type-hint them in the method signature for container resolution
- Don't write hand-rolled queue workers when `php artisan queue:work` will do — you lose Horizon, signal handling, and memory limits
- Don't rely on `pcntl_signal` directly — use `Command::trap` so the framework wires `pcntl_async_signals` and handler chaining
- Don't log inside tight loops at `info` level — use the verbosity flags to gate verbose output and avoid log spam
