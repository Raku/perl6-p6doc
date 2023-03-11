use Rakudoc::Documentable;
use Pod::To::Text;
use Rakudoc::Pod::Cache;

my class X::Rakudoc is Exception {
    has $.message;
}

my class X::Rakudoc::BadQuery is X::Rakudoc {}
my class X::Rakudoc::BadDocument is X::Rakudoc {
    has $.doc;
    has $.message;
    method message {
        "Error processing document {$!doc.gist}: $!message";
    }
}

class Rakudoc:auth<zef:coke>:api<1>:ver<0.2.4> {
    has @.doc-sources;
    has $.data-dir;
    has $!cache;
    has $!index;

    has @!extensions = <pod6 rakudoc>;

    has @.warnings;

    submethod TWEAK(
        :$doc-sources is copy,
        :$no-default-docs,
        :$data-dir,
    ) {
        $doc-sources = self.doc-sources-from-str($doc-sources)
            if $doc-sources and $doc-sources ~~ Stringy;
        $doc-sources = grep *.defined, $doc-sources<>;
        $doc-sources ||= self.doc-sources-from-str(%*ENV<RAKUDOC>);
        $doc-sources = [$doc-sources<>.grep(*.chars)];
        unless $no-default-docs {
            $doc-sources.append:
                $*REPO.repo-chain.map({.?abspath.IO // Empty})».add('doc');
        }
        @!doc-sources = map *.resolve, grep *.d, map *.IO, @$doc-sources;

        $!data-dir = self!resolve-data-dir($data-dir // %*ENV<RAKUDOC_DATA>);
    }

    role Request {
        has $.rakudoc;
    }

    role Doc {
        has $.rakudoc;
        has $.origin;
        has $.def;

        method source { ... }
        method pod { ... }
        method gist { ... }
    }

    class Doc::Documentable does Doc {
        has $.doc-source;
        has $.filename;

        has $!documentable;

        submethod TWEAK(
            :$doc-source!,
            :$filename! is copy,
        ) {
            $!doc-source = $doc-source.IO;
            $!origin = $!doc-source.add($filename);
            if $!origin.e {
                $!filename = $filename.IO;
            }
            else {
                with $!rakudoc.search-doc-sources($filename, @$!doc-source) {
                    $!filename = .first.key;
                    $!origin = $!doc-source.add($!filename);
                }
                else {
                    $!filename = $filename;
                    X::Documentable::BadDocument.new(
                        :doc(self), :message("'$!origin' does not exist")
                    ).throw;
                }
            }
        }

        method source {
            state $ //= $!origin.slurp
        }
        method pod {
            my @pod;
            @pod = $.documentable.defs.grep({.name eq $!def}).map(*.pod)
                if $!def;
            @pod || $.documentable.pod;
        }
        method gist {
            "Doc {$!origin.absolute}"
        }
        method filename {
            # Drop the extension
            my $f = $!filename.IO.extension('', :parts(1));
            # Drop the first directory (Documentable Kind dir, e.g. "Type")
            $f.SPEC.catdir($f.SPEC.splitdir($f).tail(*-1))
        }
        method documentable {
            return $_ with $!documentable;
            my $pod = $!rakudoc.cache.pod($!origin.absolute);

            {
                # Documentable is strict about Pod contents currently, and will
                # probably throw (X::Adhoc) for anything that isn't in the main
                # doc repo.
                CATCH {
                    default {
                        fail X::Rakudoc::BadDocument.new:
                            :doc(self), :message(~$_)
                    }
                }

                $!documentable = Documentable::Primary.new:
                    :pod($pod.first),
                    :$.filename,
                    :source-path($!origin.absolute);
            }
        }
    }

    class Doc::Handle does Doc {
        method source {
            state $ //= $!origin.slurp
        }
        method pod {
            # TODO Parsing Pod
            # TODO Handle $.def
            ''
        }
        method gist {
            "Doc {$!origin.?path // $!origin.gist}"
        }
    }

    class Doc::CompUnit does Doc {
        method source {
            my $prefix = $!origin.repo.prefix;
            my $source = $!origin.distribution.meta<source>;
            if $prefix && $source && "$prefix/sources/$source".IO.e {
                state $ //= "$prefix/sources/$source".IO.slurp
            }
            else {
                $!rakudoc.warn: "Module exists, but no source file for {self}";
                ''
            }
        }
        method pod {
            $!rakudoc.cache.pod($!origin.handle)
            # TODO Handle $.def
        }
        method gist {
            "Doc {$!origin.repo.prefix} {$!origin}"
        }
        method filename {
            ~ $!origin
        }
    }

    class Request::Name does Request {
        has $.name;
        has $.def;
        method Str { "'{$.name}{'.' ~ $.def if $.def}'" }
    }

    class Request::Def does Request {
        has $.def;
        method Str { "'.{$.def}'" }
    }

    class Request::Path does Request {
        has $.path;
        method Str { "'{$.path}'" }
    }

    grammar Request::Grammar {
        token TOP { <module> <definition>? | <definition> }
        token module { <-[\s.]> + }
        token definition { '.' <( <-[\s.]> + )> }
    }

    method request(Str $query) {
        return Request::Path.new: :path($query)
            if $query.IO.e;

        Request::Grammar.new.parse($query)
            or die X::Rakudoc::BadQuery.new: :message("unrecognized query: $query");

        if $/<module> {
            Request::Name.new: :name($/<module>), :def($/<definition>)
        }
        else {
            Request::Def.new: :def($/<definition>)
        }
    }

    method search(Request $req) {
        given $req {
            when Request::Name {
                # Names can match either a doc file or an installed module
                flat
                    self.search-doc-sources($req.name, self.doc-sources)
                        .map({
                            Doc::Documentable.new: :rakudoc(self),
                                :filename(.key), :doc-source(.value),
                                :def($req.def)
                        }),
                    self.search-repos(~$req.name).map({
                        Doc::Handle.new: :rakudoc(self),
                            :origin($_), :def($req.def)
                    }),
                    self!locate-curli-module(~$req.name).map({
                        Doc::CompUnit.new: :rakudoc(self),
                            :origin($_), :def($req.def)
                    }),
            }

            when Request::Def {
                self.index.def($req.def).map: {
                    Doc::Documentable.new: :rakudoc(self),
                        :filename(.key), :doc-source(.value),
                        :def($req.def);
                }
            }

            when Request::Path {
                Doc::Handle.new: :rakudoc(self), :origin(.path.IO)
            }
        }
    }

    method search-repos($str) {
        my $fragment = IO::Spec::Unix.catdir: $str.split('::');

        map -> $dist {
                | $dist.meta.<files>.keys.grep(/ '/' $fragment '.' /).map({
                    $dist.content($_)
                })
            },
            grep *.defined,
            flat $*REPO.repo-chain.map({ .?candidates($str).?head })
    }

    method search-doc-sources($str, @doc-sources) {
        my $fragment = reduce { $^a.add($^b) }, '.'.IO, | $str.split('::');

        # Add extension unless it already has one
        my @fragments = $fragment.extension(:parts(1))
                ?? $fragment
                !! @!extensions.map({ $fragment.extension($_, :parts(0)) });

        gather for @doc-sources.map(*.IO) -> $doc-source {
            for @fragments -> $fragment {
                if $doc-source.add($fragment).e {
                    take $fragment => $doc-source
                }
                else {
                    for $doc-source.dir(:test(*.starts-with('.').not))
                            .grep(*.d)
                    {
                        with .basename.IO.add($fragment) {
                            take $_ => $doc-source if $doc-source.add($_).e
                        }
                    }
                }
            }
        }
    }

    method render(Doc $doc) {
        my $text = join "\n\n",
                grep / \w /,
                map { pod2text($_).trim ~ "\n" },
                $doc.pod;

        # Should pod2text come up empty, present the raw document source
        $text ||= $doc.source;
        $text
    }

    method cache {
        return $!cache if $!cache;
        $!data-dir.mkdir unless $!data-dir.d;
        $!cache = Rakudoc::Pod::Cache.new: :cache-path($!data-dir.add('cache'));
    }

    class Index {
        has $.rakudoc;
        has $.index-dir;
        has $!defs;

        method def($needle) {
            grep { state %seen; not %seen{$_}++ },
                $!rakudoc.doc-sources.map: -> $doc-source {
                    | .map({ $_ => $doc-source })
                    with $.defs{ $doc-source }{ $needle }
                }
        }

        method defs {
            self!load unless $!defs.defined;
            $!defs
        }

        method build {
            $!index-dir.mkdir unless $!index-dir.d;
            for $!rakudoc.doc-sources -> $doc-source {
                my %defs;
                my $index = self!source-index($doc-source);
                my $docs = $!rakudoc.enumerate-docs-dir($doc-source);
                note "Indexing {+$docs} docs",
                    " from '$doc-source' in '$!index-dir'";
                for @$docs {
                    my $dd = Doc::Documentable.new: :$!rakudoc,
                        :$doc-source,
                        :filename(.IO.relative($doc-source));
                    with $dd.documentable -> $doc {
                        for $doc.defs -> $def {
                            %defs{$def.name}.push($doc.filename)
                        }
                    }
                    else {
                        when Failure {
                            $!rakudoc.warn: .exception.message
                        }
                        default {
                            .throw
                        }
                    }
                }

                $index.spurt: join '', map { ($_, |%defs{$_}).join("\t") ~ "\n" },
                        %defs.keys.sort;

                $!defs{$doc-source} = %defs;
            }
            $!defs
        }

        method !load {
            for $!rakudoc.doc-sources -> $doc-source {
                my $index = self!source-index($doc-source);
                $!defs{$doc-source} = do
                    if $index.e {
                        hash $index.lines».split("\t").map:
                                -> ($def, *@names) { $def => @names }
                    }
                    else {
                        $++ or $!rakudoc.warn: "Run 'rakudoc -b' to build index:";
                        $!rakudoc.warn: "- no index built for '$doc-source'";
                        hash Empty
                    }
                    ;
            }
        }

        method !source-index($source) {
            use nqp;
            $!index-dir.add: nqp::sha1($source.absolute)
        }
    }

    method index {
        return $!index if $!index;
        $!data-dir.mkdir unless $!data-dir.d;
        $!index = Index.new: :rakudoc(self),
                    :index-dir($!data-dir.add('index'));
    }

    method warn($warning) {
        @!warnings.push: $warning;
    }

    method !resolve-data-dir($data-dir) {
        # A major limitation is that currently there can only be a single
        # Pod::Cache instance in a program (due to precompilation guts?)
        # See https://github.com/finanalyst/raku-pod-from-cache/blob/master/t/50-multiple-instance.t
        #
        # This precludes having a read-only system-wide cache and a
        # user-writable fallback. So for now, each user must build & update
        # their own cache.

        return $data-dir.IO.resolve(:completely) if $data-dir;

        # By default, this will be ~/.cache/raku/rakudoc-data on most Unix
        # distributions, and ~\.raku\rakudoc-data on Windows and others
        my IO::Path @candidates = map *.add('rakudoc-data'),
            # Here is one way to get a system-wide cache: if all raku users are
            # able to write to the raku installation, then this would probably
            # work; of course, this will also require file locking to prevent
            # users racing against each other while updating the cache / indexes
            #$*REPO.repo-chain.map({.?prefix.?IO // Empty})
            #        .grep({ $_ ~~ :d & :w })
            #        .first(not *.absolute.starts-with($*HOME.absolute)),
            %*ENV<XDG_CACHE_HOME>.?IO.?add('raku') // Empty,
            %*ENV<XDG_CACHE_HOME>.?IO // Empty,
            $*HOME.add('.raku'),
            $*HOME.add('.perl6'),
            $*CWD;
            ;

        @candidates.first(*.f) // @candidates.first;
    }

    method !locate-curli-module($short-name) {
        # TODO This is only the first one; keep on searching somehow?
        my $cu = try $*REPO.need(CompUnit::DependencySpecification.new: :$short-name);
        $cu // Empty
    }

    method enumerate-docs-dir($doc) {
        $doc.dir.map: {
            unless .basename.starts-with('.') {
                if .d {
                    | self.enumerate-docs-dir($_)
                }
                else {
                    $_ if .extension eq any(@!extensions)
                }
            }
        }
    }

    method doc-sources-from-str($str) {
        ($str // '').split(',')».trim
    }
}
