use Pod::Utils;
use Pod::Utils::Build;

#| Enum to classify all "kinds" of Documentable
enum Kind is export (Type      => "type"     , Language => "language",
                     Programs  => "programs" , Syntax   => "syntax"  ,
                     Reference => "reference", Routine  => "routine" );

#| List of the subdirectories that contain indexable pods by default
constant DOCUMENTABLE-DIRS is export = ["Language", "Type", "Programs", "Native"];

class X::Documentable::TitleNotFound is Exception {
    has $.filename;
    method message() {
        "=TITLE element not found in $.filename pod file."
    }
}

class X::Documentable::SubtitleNotFound is Exception {
    has $.filename;
    method message() {
        "=SUBTITLE element not found in $.filename pod file."
    }
}

class X::Documentable::MissingMetadata is Exception {
    has $.filename;
    has $.metadata;
    method message() {
        "$.metadata not found in $.filename pod file config. \n"                ~
        "The first line of the pod should contain: \n"                          ~
        "=begin pod :kind('<value>') :subkind('<value>') :category('<value>') \n"
    }
}

grammar Documentable::Heading::Grammar {
    token operator    { infix  | prefix   | postfix  | circumfix | postcircumfix | listop }
    token routine     { sub    | method   | term     | routine   | submethod     | trait  }
    token syntax      { twigil | constant | variable | quote     | declarator             }
    token subkind     { <routine> | <syntax> | <operator> }
    token name        { .*  } # is rw
    token single-name { \S* } # infix

    rule the-foo-infix {^\s*[T|t]'he' <single-name> <subkind>\s*$}
    rule infix-foo     {^\s*<subkind> <name>\s*$}

    rule TOP { <the-foo-infix> | <infix-foo> }
}

class Documentable::Heading::Actions {
    has Str  $.dname     = '';
    has      $.dkind     ;
    has Str  $.dsubkind  = '';
    has Str  $.dcategory = '';

    method name($/) {
        $!dname = $/.Str;
    }

    method single-name($/) {
        $!dname = $/.Str;
    }

    method subkind($/) {
        $!dsubkind = $/.Str.trim;
    }

    method operator($/) {
        $!dkind     = Kind::Routine;
        $!dcategory = "operator";
    }

    method routine($/) {
        $!dkind     = Kind::Routine;
        $!dcategory = $/.Str;
    }

    method syntax($/) {
        $!dkind     = Kind::Syntax;
        $!dcategory = $/.Str;
    }
}

#| Converts Lists of Pod::Blocks to String
multi textify-pod (Any:U        , $?) is export { '' }
multi textify-pod (Str:D      \v, $?) is export { v }
multi textify-pod (List:D     \v, $separator = ' ') is export { v».&textify-pod.join($separator) }
multi textify-pod (Pod::Block \v, $?) is export {
    # core module
    use Pod::To::Text;
    pod2text v;
}

#| Everything documented inherits from this class
class Documentable {

    has Str  $.name;
    has      $.pod  is required("Needs an actual document");
    has Kind $.kind is required("Is essential metadata");
    has      @.subkinds   = [];
    has      @.categories = [];

    submethod BUILD (
        :$!name,
        :$!kind!,
        :@!subkinds,
        :@!categories,
        :$!pod!,
    ) {}

    method english-list () {
        return '' unless @!subkinds.elems;
        @!subkinds > 1
                    ?? @!subkinds[0..*-2].join(", ") ~ " and @!subkinds[*-1]"
                    !! @!subkinds[0]
    }

    method human-kind() {
        $!kind eq Kind::Language
            ?? 'language documentation'
            !! @!categories eq 'operator'
            ?? "@!subkinds[] operator"
            !! self.english-list // $!kind;
    }

    method categories() {
        return @!categories if @!categories;
        return @!subkinds;
    }
}

#| Every type of page generated, must implement this role
role Documentable::DocPage {
    method render (| --> Hash) { ... }
}

# these chars cannot appear in a unix filesystem path
sub good-name($name is copy --> Str) {
    # / => $SOLIDUS
    # % => $PERCENT_SIGN
    # ^ => $CIRCUMFLEX_ACCENT
    # # => $NUMBER_SIGN
    my @badchars  = ["/", "^", "%"];
    my @goodchars = @badchars
                    .map({ '$' ~ .uniname      })
                    .map({ .subst(' ', '_', :g)});

    $name = $name.subst(@badchars[0], @goodchars[0], :g);
    $name = $name.subst(@badchars[1], @goodchars[1], :g);

    # if it contains escaped sequences (like %20) we do not
    # escape %
    if ( ! ($name ~~ /\%<xdigit>**2/) ) {
        $name = $name.subst(@badchars[2], @goodchars[2], :g);
    }

    return $name;
}

sub rewrite-url($s, $prefix?) {
    given $s {
        when {.starts-with: 'http' or
              .starts-with: '#'    or
              .starts-with: 'irc'     } { $s }
        default {

            my @parts   = $s.split: '/';
            my $name    = good-name(@parts[*-1]);
            my $new-url = @parts[0..*-2].join('/') ~ "/$name";

            if ($new-url ~~ /\.$/) { $new-url = "{$new-url}.html" }

            return "/{$prefix}{$new-url}" if $prefix;
            return $new-url;

        }
    }
}

class Documentable::Index is Documentable {
    has $.origin;
    has @.meta;

    method new(
        :$pod!,
        :$meta!,
        :$origin!
    ) {

        my $name;
        if $meta.elems > 1 {
            my $last = textify-pod $meta[*-1];
            my $rest = $meta[0..*-2];
            $name = "$last ($rest)";
        } else {
            $name = textify-pod $meta;
        }

        nextwith(
            kind     => Kind::Reference,
            subkinds => ['reference'],
            name     => $name.trim,
            :$pod,
            :$origin,
            :$meta
        );
    }

    method url() {
        my $index-text = recurse-until-str($.pod).join;
        my @indices    = $.pod.meta;
        my $fragment = qq[index-entry{@indices ?? '-' !! ''}{@indices.join('-')}{$index-text ?? '-' !! ''}$index-text]
                     .subst('_', '__', :g).subst(' ', '_', :g);

        return $.origin.url ~ "#" ~ good-name($fragment);
    }
}

class Documentable::Secondary is Documentable {

    has $.origin;
    has Str $.url;
    has Str $.url-in-origin;

    method new(
        :$kind!,
        :$name!,
        :@subkinds,
        :@categories,
        :$pod!,
        :$origin
    ) {

        my $url = "/{$kind.Str.lc}/{good-name($name)}";
        my $url-in-origin = $origin.url ~ "#" ~textify-pod($pod[0]).trim.subst(/\s+/, '_', :g);

        # normalize the pod
        my $title = "($origin.name()) @subkinds[] $name";
        my $new-head = Pod::Heading.new(
            level    => 2,
            contents => [ pod-link($title, $url-in-origin) ]
        );
        my @chunk = flat $new-head, $pod[1..*-1];
        @chunk = pod-lower-headings( @chunk, :to(2) );

        nextwith(
            :$kind,
            :$name,
            :@subkinds,
            :@categories,
            :pod(@chunk),
            :$origin,
            :$url,
            :$url-in-origin
        );
    }

}
class Documentable::Primary is Documentable {

    has Str  $.summary;
    has Str  $.url;
    has Str  $.filename;
    has Str  $.source-path;
    #| Definitions indexed in this pod
    has @.defs;
    #| References indexed in this pod
    has @.refs;

    method new (
        Str :$filename!,
        Str :$source-path!,
            :$pod!
    ) {
        self.check-pod($pod, $filename);
        my $kind = Kind( $pod.config<kind>.lc );

        # proper name from =TITLE
        my $title = $pod.contents[0];
        my $name = recurse-until-str($title);
        $name = $name.split(/\s+/)[*-1] if $kind eq Kind::Type;
        # summary from =SUBTITLE
        my $subtitle = $pod.contents[1];
        my $summary = recurse-until-str($subtitle);

        my $url = do given $kind {
            when    Kind::Type {"/{$kind.Str}/$name"    }
            default            {"/{$kind.Str}/$filename"}
        }

        # use metadata in pod config
        my @subkinds   = $pod.config<subkind>.List;
        my @categories = $pod.config<category>.List;

        nextwith(
            :$pod,
            :$kind,
            :$name,
            :$summary,
            :$url
            :@subkinds,
            :@categories,
            :$filename,
            :$source-path
        );
    }

    submethod TWEAK(:$pod) {
        self.find-definitions(:$pod);
        self.find-references(:$pod);
    }

    method check-pod($pod, $filename?) {
        # check title
        my $title = $pod.contents[0];
        die X::Documentable::TitleNotFound.new(:$filename)
        unless ($title ~~ Pod::Block::Named and $title.name eq "TITLE");

        # check subtitle
        my $subtitle = $pod.contents[1];
        die X::Documentable::SubtitleNotFound.new(:$filename)
        unless ($subtitle ~~ Pod::Block::Named and $subtitle.name eq "SUBTITLE");

        # check metadata
        my $correct-metadata = $pod.config<kind>    and
                               $pod.config<subkind> and
                               $pod.config<category>;

        die X::Documentable::MissingMetadata.new(:$filename, metadata => "kind")
        unless $correct-metadata;
    }

    method parse-definition-header(Pod::Heading :$heading --> Hash) {
        my @header;
        try {
            @header := $heading.contents[0].contents;
            CATCH { return %(); }
        }

        my %attr;
        if (
            @header[0] ~~ Pod::FormattingCode and
            +@header eq 1 # avoid =headn X<> and X<>
        ) {
            my $fc = @header.first;
            return %() if $fc.type ne "X";

            my @meta = $fc.meta[0]:v.flat.cache;
            my $name = (@meta > 1) ?? @meta[1]
                                !! textify-pod($fc.contents[0], '');

            %attr = name       => $name.trim,
                    kind       => Kind::Syntax,
                    subkinds   => @meta || (),
                    categories => @meta || ();

        } else {
            my $g = Documentable::Heading::Grammar.parse(
                textify-pod(@header, '').trim,
                :actions(Documentable::Heading::Actions.new)
            ).actions;

            # no match, no valid definition
            return %attr unless $g;
            %attr = name       => $g.dname,
                    kind       => $g.dkind,
                    subkinds   => $g.dsubkind.List,
                    categories => $g.dcategory.List;
        }

        return %attr;
    }

    method find-definitions(
            :$pod,
        Int :$min-level = -1,
        --> Int
    ) {

        my @pod-section = $pod ~~ Positional ?? @$pod !! $pod.contents;
        my int $i = 0;
        my int $len = +@pod-section;
        while $i < $len {
            NEXT {$i = $i + 1}
            my $pod-element := @pod-section[$i];
            # only headers are possible definitions
            next unless $pod-element ~~ Pod::Heading;
            # if we have found a heading with a lower level, then the subparse
            # has been finished
            return $i if $pod-element.level <= $min-level;

            my %attr = self.parse-definition-header(:heading($pod-element));
            next unless %attr;

            # Perform sub-parse, checking for definitions elsewhere in the pod
            # And updating $i to be after the places we've already searched
            my $new-i = $i + self.find-definitions(
                            :pod(@pod-section[$i+1..*]),
                            :min-level(@pod-section[$i].level),
                        );

            # At this point we have a valid definition
            my $created = Documentable::Secondary.new(
                origin => self,
                pod => @pod-section[$i .. $new-i],
                |%attr
            );

            @!defs.push: $created;

            $i = $new-i + 1;
        }
        return $i;
    }

    method find-references(:$pod) {
        if $pod ~~ Pod::FormattingCode && $pod.type eq 'X' {
        if ($pod.meta) {
            for @( $pod.meta ) -> $meta {
                @!refs.push: Documentable::Index.new(
                    pod    => $pod,
                    meta   => $meta,
                    origin => self
                )
            }
        } else {
                @!refs.push: Documentable::Index.new(
                    pod    => $pod,
                    meta   => $pod.contents[0],
                    origin => self
                )
        }
        }
        elsif $pod.?contents {
            for $pod.contents -> $sub-pod {
                self.find-references(:pod($sub-pod)) if $sub-pod ~~ Pod::Block;
            }
        }
    }

}
