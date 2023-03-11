use Test;

%*ENV<RAKUDOC_TEST> = '1';
%*ENV<RAKUDOC> = 't/test-doc';

my @tests =
    \('test-no-match'), [ False, / ^ $ /, / No .* 'test-no-match' / ],
    \(:help), [ True, / ^ Usage /, / ^ $ /],
    \('Map'), [ True, / 'class Map' \N+ 'does Associative' / ],
    \('X::IO'), [ True, / 'role X::IO does X::OS' / ],
    \('Hash.classify-list'), [ True, / 'method classify-list' / ],
    ;

plan +@tests / 2;

# The following is a way to test `MAIN`s from Rakudoc::CMD directly without
# triggering usage. The C<use Rakudoc::CMD> must be in a new lexical scope,
# where its MAIN will be harmlessly installed but not jumped to.
BEGIN sub MAIN(|) { };

for @tests -> $args, $like {
    subtest "MAIN {$args.gist}" => {
        my ($result-is, $out-like, $err-like) = @$like;
        plan $err-like.defined ?? 3 !! 2;

        my ($result, $out, $err) = run-test $args;

        is $result, $result-is, "returns $result-is";
        like $out, $out-like, "output like {$out-like.gist}";
        like $err, $_, "output like {.gist}" with $err-like;
    }
}

sub run-test($args) {
    use IO::MiddleMan;
    use Rakudoc::CMD;

    my $result;

    my $*USAGE = "Usage:\n  Mock USAGE for testing\n";

    my ($out, $err) = map { IO::MiddleMan.hijack: $_ }, $*OUT, $*ERR;
    try $result = Rakudoc::CMD::MAIN(|$args);
    for $err, $out { .mode = 'normal' }
    die $! if $!;

    ($result, ~$out, ~$err);
}
