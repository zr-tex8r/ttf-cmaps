use strict;
use XML::Simple;
use File::Copy 'copy';
my $program = 'gen-override';

my $ttx = 'ttx';
my $kpsewhich = 'kpsewhich';
my $tempb = '__govr'.$$.'x';

our (%cmap12, @cmap14, @ivslist);
require "shscmap.pl";
require "../aj17-ivs.pl";

my ($in_file, $out_file);
my (%tocid, %map);

sub main {
  $in_file = shift(@ARGV);
  info("input font file", $in_file);
  local $_ = $in_file; s/\.ttf$//;
  $out_file = "override-$_.txt";
  info("output file", $out_file);
  make_tocid();
  my $xfnt = dump_font();
  analyze($xfnt);
  generate_override();
}

# make SHS-glyph-name -> AJ1-CID mapping for kanji glyphs
sub make_tocid {
  my %int = map {
    my ($uc1, $uc2, $cid) = @$_; "$uc1,$uc2" => $cid
  } (@ivslist);
  foreach (@cmap14) {
    my ($uc1, $uc2, $n) = @$_;
    my $cid = $int{"$uc1,$uc2"} or next;
    $tocid{$n} = $cid;
  }
}

sub analyze {
  my ($xfnt) = @_; local ($_);
  my $nglyphs = $xfnt->{maxp}{numGlyphs}{value};
  info("glyph count", $nglyphs);

  my @gnames = map { $_->{name} } (@{$xfnt->{GlyphOrder}{GlyphID}});
  (scalar(@gnames) == $nglyphs) or error("inconsistency on glyph count");

  L1:foreach my $gid (0 .. $#gnames) {
    $_ = $gnames[$gid]; my ($uc);
    if (!m/^cid/) {
      if (($uc) = m/^uni([0-9A-F]{4})$/) { $uc = hex($uc); }
      elsif (($uc) = m/^u([0-9A-F]+)$/) { $uc = hex($uc); }
      else { next L1; }
      $_ = $cmap12{$uc} or next L1;
    } # now $_ is SHS glyph name
    my $cid = $tocid{$_} or next L1;
   #info($gid, $_, $cid);
    $map{$cid} = $gid;
  }
}

sub dump_font {
  if (-f "$in_file.xml") {
    info("using intermediate file", "$in_file.xml");
    copy("$in_file.xml", "$tempb-f.ttx");
  } else {
    my $pfnt = kpse($in_file);
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
      'GlyphID',
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
  (-f $f) and return $f;
  system("$kpsewhich --help 1>$tempb-1.out 2>$tempb-2.out");
  unlink(glob("$tempb-*.out"));
  ($? == 0) or error("file not found", $f);
  local $_ = `$kpsewhich $f`; chomp($_);
  (-f $_) or error("file not found on search path", $f);
  return $_;
}

sub info {
  print STDERR (join(": ", $program, @_), "\n");
}
sub error {
  info(@_); exit(1);
}

main();
