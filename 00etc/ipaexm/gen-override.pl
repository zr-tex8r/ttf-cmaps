use strict;
use XML::Simple;
use File::Copy 'copy';
my $program = 'gen-override';

my $ttx = 'ttx';
my $tempb = '__govr'.$$.'x';

my $in_file = 'ipaexm.ttf';
my $out_file = 'override-ipaex.txt';

my (%map);

sub main {
  info("input font file", $in_file);
  info("output file", $out_file);
  my $xfnt = dump_font();
  analyze($xfnt);
  generate_override();
}

sub analyze {
  my ($xfnt) = @_; local ($_);
  my $nglyphs = $xfnt->{maxp}{numGlyphs}{value};
  info("glyph count", $nglyphs);

  my @gnames = map { $_->{name} } (@{$xfnt->{GlyphOrder}{GlyphID}});
  (scalar(@gnames) == $nglyphs) or error("inconsistency on glyph count");

  foreach my $gid (0 .. $#gnames) {
    $_ = $gnames[$gid];
    my ($cid) = (m/^aj(\d+)$/) or next;
    $map{$cid} = $gid;
  }
}

sub dump_font {
  if (-f "$in_file.xml") {
    info("using intermediate file", "$in_file.xml");
    copy("$in_file.xml", "$tempb-f.ttx");
  } else {
    my $pfnt = kpse($in_file) or error("file not found on search path", $in_file);
    info("font file path", $pfnt);
    my ($fext) = ($pfnt =~ m/(\.\w+)$/);
    unlink(glob("$tempb-f*.*"));
    copy($pfnt, "$tempb-f$fext") or die;
    info("dump font with TTX...");
    system("$ttx -x post -x glyf -x CFF -x cmap $tempb-f$fext 1>$tempb-f1.out");
    ($? == 0 && -f "$tempb-f.ttx")
      or error("failure in ttx", "$tempb-f$fext");
  }
  info("parse dump data...");
  my $xfnt = XMLin("$tempb-f.ttx",
    ForceArray => [
      'Alternate',
      'AlternateSet',
      'AlternateSubst',
      'FeatureIndex',
      'FeatureRecord',
      'GlyphID',
      'Ligature',
      'LigatureSet',
      'LigatureSubst',
      'Lookup',
      'LookupListIndex',
      'ScriptRecord',
      'SingleSubst',
      'Substitution',
      'cmap_format_12',
      'cmap_format_14',
      'cmap_format_4',
      'map',
      'mtx',
      'namerecord',
    ],
    KeyAttr => []);
  (ref $xfnt eq 'HASH') or error("cannot parse XML properly");
  unlink(glob("$tempb-f*.*"));
  info("done");
  return $xfnt;
}

sub generate_override {
  my (@cnks);
  foreach my $cid (sort { $a <=> $b } (keys %map)) {
    push(@cnks, sprintf("%d\t%d\n", $cid, $map{$cid}));
  }
  write_whole($out_file, join('', @cnks));
}

sub read_whole {
  my ($p) = @_; local ($_, $/);
  open(my $h, '<', $p) or error("caanot open for read", $p);
  binmode($h); $_ = <$h>;
  close($h);
  return $_;
}
sub write_whole {
  my ($p, $d) = @_; local ($_);
  open(my $h, '>', $p) or error("caanot open for write", $p);
  binmode($h); print $h ($d);
  close($h);
}

sub kpse {
  my ($f) = @_;
  local $_ = `kpsewhich $f`; chomp($_);
  return ($_ eq '') ? undef : $_;
}

sub info {
  print STDERR (join(": ", $program, @_), "\n");
}
sub error {
  info(@_); exit(1);
}

main();
