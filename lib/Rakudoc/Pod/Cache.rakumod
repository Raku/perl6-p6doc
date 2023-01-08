unit class Rakudoc::Pod::Cache;

has %.sources is SetHash;

has IO::Path $!cache-path;
has $!precomp-repo;
has %!errors;
has %!ids;


submethod BUILD(
    :$cache-path = 'rakudoc_cache',
)
{

  # "File" class was deprecated; use the FileSystem if it's available, fall back to deprecated if not.
  # (should now work on both new and old rakudos, avoiding deprecation notice where possible
  my $class = ::("CompUnit::PrecompilationStore::FileSystem");
  if $class ~~ Failure {
    $class = ::("CompUnit::PrecompilationStore::File");
  }

  $!cache-path = $cache-path.IO.resolve(:completely);
  $!precomp-repo = CompUnit::PrecompilationRepository::Default.new(
    :store($class.new(:prefix($!cache-path))),
  );
}

method !compunit-handle($pod-file-path) {
    my $t = $pod-file-path.IO.modified;
    my $id = CompUnit::PrecompilationId.new-from-string($pod-file-path);
    %!ids{$pod-file-path} = $id;
    my ($handle, $) = $!precomp-repo.load( $id, :src($pod-file-path), :since($t) );
    unless $handle {
        #note "Caching '$pod-file-path' to '$!cache-path'";
        $handle = $!precomp-repo.try-load(
            CompUnit::PrecompilationDependency::File.new(
                :src($pod-file-path),
                :$id,
                :spec(CompUnit::DependencySpecification.new(:short-name($pod-file-path))),
            )
        );
        #note "    - Survived with handle {$handle // 'NULL'}";
    }

    ++%!sources{$pod-file-path};
    return $handle;
}

#| pod(Str $pod-file-path) returns the pod tree in the pod file
multi method pod(CompUnit::Handle $handle) {
    use nqp;
    nqp::atkey($handle.unit, '$=pod')
}

multi method pod(IO::Path $pod-file-path) {
    my $handle;
    # Canonical form for lookup consistency
    my $src = $pod-file-path.resolve(:completely).absolute;
    if %!ids{$src}:exists {
        $handle = $!precomp-repo.try-load(
            CompUnit::PrecompilationDependency::File.new(
                :$src,
                :id(%!ids{$src})
                ),
            );
    }
    else {
        $handle = self!compunit-handle($src);
    }

    self.pod: $handle;
}

multi method pod(Str $pod-file-path) {
    self.pod: $pod-file-path.IO;
}
