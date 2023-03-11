use Test;
use Rakudoc;
use Pod::To::Text;

use File::Directory::Tree;

%*ENV<RAKUDOC_TEST> = '1';
%*ENV<RAKUDOC> = 't/test-doc';

plan 12;

my $data-dir = 't/test-cache'.IO;
rmtree $data-dir;

nok $data-dir.e, "Test data-dir removed at start";
my $rakudoc = Rakudoc.new: :no-default-docs, :$data-dir;
nok $data-dir.e, "Rakudoc.new does not create data dir";
my $index = $rakudoc.index;
ok $data-dir.d, "Rakudoc.index creates data dir";

nok $index.index-dir.e, "Rakudoc.index does not create index dir";

is $rakudoc.warnings.elems, 0, "No warnings issued before lookup";
is $index.def('mro'), (), "Lookup in empty index returns empty";
diag "($_)" for $rakudoc.warnings;
ok $rakudoc.warnings.elems > 0, "Warnings issued for non-indexed source";
$rakudoc.warnings = Empty;
nok $index.index-dir.e, "Lookup does not create index dir";

$index.build;
ok $index.index-dir.d, "Rakudoc.index creates index dir";
diag "($_)" for $rakudoc.warnings;
is $rakudoc.warnings.elems, 2, "Test docs contain 2 non-Documentable docs";
$rakudoc.warnings = Empty;

subtest 'Validate every indexed source', {
    my $names = set $index.defs.values.map(*.values».list).flat;
    plan 1 + $names.elems;
    ok $names.elems > 5, "At least 5 test docs contain defs (sanity)";
    for $names.keys -> $name {
        my @docs = $rakudoc.search: $rakudoc.request: $name;
        is +@docs, 1, "Doc found for name '$name'";
    }
}

subtest 'Validate lookup of every def', {
    my $defs = set $index.defs.values.map(*.keys».list).flat;
    plan 1 + $defs.elems * 2;
    ok $defs.elems > 5, "Test docs contain at least 5 distinct defs (sanity)";
    for $defs.keys.sort -> $def {
        my @entries = $index.def($def);

        ok +@entries > 0, "Look up entries for '$def' (found {+@entries})";

        my @texts = @entries.map: {
                my $doc = Doc::Documentable.new: :$rakudoc,
                    :filename(.key), :doc-source(.value),
                    :$def;
                pod2text($doc.pod)
            };

        next if is +@entries, +@texts.grep(*.contains($def)),
            "All entries for '$def' can be displayed";

        diag "{.key.raku}\n{.value.raku}\n" for @entries Z=> @texts;
    }
}
