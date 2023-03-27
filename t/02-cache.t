use Test;
use File::Temp;
use Rakudoc::Pod::Cache;

plan 6;

my $test-doc = 't/test-doc/Type/Map.rakudoc';

my $cache-path = tempdir.IO.add('cache');
my $pc = Rakudoc::Pod::Cache.new: :$cache-path;

isa-ok $pc, Rakudoc::Pod::Cache,
    "Create cache object";

is $cache-path.e, False,
    "Cache dir is not created until needed";

like $pc.pod($test-doc).?first.^name, /^ 'Pod::'/,
    "pod('relative/path.ext') returns a Pod";

is $cache-path.d, True,
    "Cache dir is created when needed";

like $pc.pod($test-doc.IO).?first.^name, /^ 'Pod::'/,
    "pod('relative/path.ext'.IO) returns a Pod";

throws-like { $pc.pod('nonexistent') }, X::Multi::NoMatch,
    "pod('nonexistent') dies";
