use Test;
use Rakudoc;

%*ENV<RAKUDOC_TEST> = '1';
%*ENV<RAKUDOC> = 't/test-doc';

plan 2;

my $rakudoc = Rakudoc.new;

subtest "language" => {
    plan 3;
    my $doc = Doc::Documentable.new: :$rakudoc,
                :doc-source(%*ENV<RAKUDOC>.IO),
                :filename('Language'.IO.add('operators.rakudoc'));
    isa-ok $doc, Rakudoc::Doc::Documentable, "Doc repr for Language/operators";
    like $doc.gist, rx/operators/, "Gist looks okay";
    like $rakudoc.render($doc), rx/Operators/, "Render looks okay";
}

subtest "type" => {
    plan 4;

    my $doc = Doc::Documentable.new: :$rakudoc,
                :doc-source(%*ENV<RAKUDOC>.IO),
                :filename('Type'.IO.add('Any.rakudoc'));
    like $rakudoc.render($doc), rx:s/class Any/,
        "Render looks okay";

    $doc = Doc::Documentable.new: :$rakudoc,
                :doc-source(%*ENV<RAKUDOC>.IO),
                :filename('Type'.IO.add('Any.rakudoc')),
                :def<root>;
    like $rakudoc.render($doc), rx:s/Subparsing/,
        "def = 'root' shows root portion";
    unlike $rakudoc.render($doc), rx:s/class Any/,
        "def = 'root' doesn't show parent content";

    $doc = Doc::Documentable.new: :$rakudoc,
                :doc-source(%*ENV<RAKUDOC>.IO),
                :filename('Type'.IO.add('Any.rakudoc')),
                :def<notfound>;
    like $rakudoc.render($doc), rx:s/class Any/,
        "def = 'notfound' shows full doc";
}
