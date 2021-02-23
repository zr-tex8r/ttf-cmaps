use strict;
use XML::Simple;
use File::Basename 'dirname';
use File::Copy 'copy';
my $program = 'glymatch';
my $version = '0.4.0';
my $mod_date = '2021/02/24';

sub show_usage {
  print(<<"EOT");
This is $program, version $version <$mod_date>
Usage: $program [<option>]... <in-font-file>
Options:
  -r/--override <file>  Specify override mapping file
  -o/--output <file>    Specify output CMap file name
  -j/--json             Output in CMJ format
  -i/--index            Specify font index in TTC/OTC files
     --cmapver <val>    Specify CMap version
  -v/--verbose          Show more messages
     --info             Output mapping info to stdout
  -h/--help             Show help and exit
  -V/--version          Show version and exit
EOT
}

my $ttx = 'ttx';
my $kpsewhich = 'kpsewhich';
my $interm_sfx = '.xml';
my $tempb = '__glym'.$$.'x';
my $owndir = dirname($0);

my $verbose = 0;
my $out_info = 0;
my $out_json = 0;
my $cmapver = 1.000;
my ($in_file, $out_file, $override_file, $font_index);

my (@gnames, %gids, %ucmap, %ivsmap, %gsubst, $psname, $jp04default);
my (@override, @gmatch);
require "$owndir/aj17-glyphs.pl";
require "$owndir/aj17-ivs.pl";
our (@glyphs, @ivslist);

#use Data::Dumper;
#$Data::Dumper::Sortkeys = 1;
#$Data::Dumper::Indent = 1;
#$Data::Dumper::Terse = 1;
#sub digest {
#  local ($_) = @_; (ref $_) and $_ = Dumper($_); s/\s+/ /g;
#  return (length($_) <= 128) ? $_ : (substr($_, 0, 125)."...");
#}

my @simpfeat = (
'jp04','jp83','jp78','hojo','nlck','trad','vert','vrt2','pwid','fwid',
'hwid','twid','qwid','hkna','vkna','pkna','ruby','ital','zero','sups',
'subs','numr','dnom','sinf','frac','expt','nalt',
);
my @compfeat = (
'liga','ccmp','dlig','afrc',
);

my @important_cid = (
  0..94, 97, 99..103, 107, 109, 117, 123, 126, 129, 134, 139, 140, 142, 144,
  145, 148, 150..154, 157..185, 187..214, 216..222, 231..324, 326..389, 631,
  633..4089, 7479..7482, 7491, 7494, 7495, 7498, 7499, 7502, 7503, 7506,
  7507, 7508, 7511, 7514, 7515, 7516, 7519, 7522, 7523, 7526, 7527, 7530,
  7531, 7534, 7535, 7538, 7539, 7542, 7545, 7554..7586, 7588, 7590, 7592,
  7593, 7595, 7596, 7598, 7599, 7601..7611, 7613..7632, 7887..7939, 8005,
  8006, 8007, 8038, 8040, 8042, 8043, 8044, 8047, 8055, 8092..8101, 8323,
  8359..8717,
);

my %adjust_map = (
   231 => [0x0020, ["hwid"]],
   233 => [0x0022, ["hwid"]],
   238 => [0x0027, ["hwid"]],
   295 => [0x0060, ["hwid"]],
   326 => [0x0020, ["hwid"]],
  1993 => [0x663B, []],
  7626 => [0x221A, []],
  7627 => [0x22A5, []],
  7628 => [0x2220, []],
  7631 => [0x2229, []],
  7632 => [0x222A, []],
  7897 => [0x2026, ["vert"]],
  7898 => [0x2025, ["vert"]],
  8404 => [0x5307, []],
  8422 => [0xFA10, []],
  8436 => [0x5BEC, []],
  8443 => [0xFA11, []],
  8476 => [0x661E, []],
  8489 => [0xF929, []],
  8494 => [0x6801, []],
  8542 => [0xFA15, []],
  8561 => [0x7462, []],
  8592 => [0x7D5C, []],
  8632 => [0xFA24, []],
  8686 => [0xF9DC, []],
  8696 => [0x9755, []],
);

sub main {
  read_option();
  info("input font file", $in_file);
  info("output CMap file", $out_file);
  if (defined $override_file) {
    info("override mapping file", $override_file);
    load_override();
  }
  my $xfnt = dump_font();
  analyze($xfnt);
  adjust_gsub($xfnt);
  glyph_match();
  if ($out_json) {
    generate_json();
  } else {
    generate_cmap();
  }
  if ($out_info) {
    output_info();
  }
}

#-----------------------------------------------------------

sub load_override {
  local $_ = read_whole($override_file);
  my ($lno, $oc) = (0, 0);
  foreach (split(m/\n/, $_)) {
    (m/^\d/) or next; $lno += 1;
    my ($gfrm, $gto) = m/^(\d+)\s+(\d+)(?:\s.*)?$/
      or error("syntax error in mapping file", "line $lno", $override_file);
    ($gfrm < 65536 && $gto < 65536) or next;
    $override[$gfrm] = $gto-0; $oc += 1;
  }
  info("override count", $oc);
}

sub glyph_match {
  my %comp = map { $_ => 1 } (@compfeat);

  my %ivs;
  foreach my $e (@ivslist) {
    my ($uc1, $uc2, $cid) = @$e;
    (exists $ivs{$cid}) or $ivs{$cid} = "$uc1,$uc2";
  }

  L1:foreach my $cid (1 .. $#glyphs) {
    if (defined $override[$cid]) {
      $gmatch[$cid] = $override[$cid];
      next;
    }

    if (exists $ivs{$cid}) {
      my $gc = $ivsmap{$ivs{$cid}};
      if (defined $gc) {
        $gmatch[$cid] = $gc;
        next;
      }
    }

    my $e = $glyphs[$cid]; (ref $e) or next;
    my ($sname, $ucs, $feas) = @$e;
    my $gc = join(',', map {
      my $gc = $ucmap{$_}; (defined $gc) or next L1;
      ($jp04default) ? $gsubst{jp90}{$gc} : $gc
    } (@$ucs));

    foreach my $fea (@$feas) {
      my $ngc = $gsubst{$fea}{$gc}; (defined $ngc) or next L1;
      $gc = $ngc;
    }
    $gmatch[$cid] = $gc;
  }

  L2:foreach my $cid (sort { $a <=> $b } (keys %adjust_map)) {
    (!defined $gmatch[$cid]) or next;
    my ($uc, $feas) = @{$adjust_map{$cid}};
    my $gc = $ucmap{$uc}; (defined $gc) or next;
    foreach my $fea (@$feas) {
      my $ngc = $gsubst{$fea}{$gc}; (defined $ngc) or next L2;
      $gc = $ngc;
    }
    #info("adjust", "$cid->$gc");
    $gmatch[$cid] = $gc;
  }

  my %gm = map { $_ => $gmatch[$_] } (grep { defined $gmatch[$_] } (1 .. $#glyphs));
  my %gmr = reverse %gm;
  my ($mcf, $gcf) = (scalar(keys %gm), $#glyphs);
  my ($mct, $gct) = (scalar(keys %gmr), scalar(@gnames));
  info("match count (source)", "$mcf (out of $gcf)");
  info("match count (target)", "$mct (out of $gct)");

  foreach my $cid (@important_cid) {
    # explicit notdef, just in case
    (defined $gmatch[$cid]) or $gmatch[$cid] = 0;
  }
}

sub output_info {
  foreach my $cid (1 .. $#glyphs) {
    my $gc = $gmatch[$cid]; my $sn = $glyphs[$cid][0];
    if (defined $gc && $gc != 0) {
      printf("%05d > %05d / %-24s: %s\n", $cid, $gc, $gnames[$gc], $sn);
    } else {
      printf("%05d - %-32s: %s\n", $cid, "", $sn);
    }
  }
}

#-----------------------------------------------------------

sub glyphid {
  my @r = map {
    (exists $gids{$_}) or error("bad glyph name", $_);
    $gids{$_}
  } (@_);
  return (wantarray) ? @r : $r[0];
}

sub analyze {
  my ($xfnt) = @_; my (@xs); local ($_);
  my $nglyphs = $xfnt->{maxp}{numGlyphs}{value};
  info("glyph count", $nglyphs);

  # GlyphOrder
  @gnames = map { $_->{name} } (@{$xfnt->{GlyphOrder}{GlyphID}});
  (scalar(@gnames) == $nglyphs) or error("inconsistency on glyph count");
  %gids = map { $gnames[$_] => $_ } (0 .. $#gnames);

  # name
  @xs = grep { $_->{nameID} == 6 } (
    @{$xfnt->{name}{namerecord}}
  );
  (@xs) or error("no PostScript name records");
  $_ = $xs[0]{content}; s/^\s+//; s/\s+$//;
  (m/^[\x21-\x7E]+$/ && !m|[\[\]\(\)\{\}\<\>\/\%]|) or error("bad PostScript font name");
  $psname = $_; info("PostScript font name", $psname);

  # cmap
  @xs = grep {
    ($_->{platformID} == 3 && $_->{platEncID} == 1) ||
    ($_->{platformID} == 3 && $_->{platEncID} == 10) ||
    ($_->{platformID} == 0 && $_->{platEncID} == 5)
  } (
    @{$xfnt->{cmap}{cmap_format_12} || []},
    @{$xfnt->{cmap}{cmap_format_4} || []}
  );
  (@xs) or error("no available cmaps");
  my ($pid, $eid) = ($xs[0]{platformID}, $xs[0]{platEncID});
  info("cmap found", "pid=$pid,eid=$eid");
  %ucmap = map {
    hex($_->{code}) => glyphid($_->{name})
  } (@{$xs[0]{map}});

  @xs = grep {
    ($_->{platformID} == 0 && $_->{platEncID} == 5)
  } (
    @{$xfnt->{cmap}{cmap_format_14} || []},
  );
  if (@xs) {
    info("cmap-14 found");
    %ivsmap = map {
      my ($uv, $uvs, $n) = (hex($_->{uv}), hex($_->{uvs}), $_->{name});
      my $gc = (defined $n) ? glyphid($n) : $ucmap{$uv};
      "$uv,$uvs" => $gc
    } (@{$xs[0]{map}});
  }

  # GSUB
  my %lidx;
  foreach my $stag ('DFLT', 'kana', 'hani', 'latn') {
    @xs = grep {
      $_->{ScriptTag}{value} eq $stag
    } (@{$xfnt->{GSUB}{ScriptList}{ScriptRecord} || []});
    (@xs) and last;
  }
  (@xs) or error("no DFLT script record");
  my @fidx = map {
    $_->{value}
  } (@{$xs[0]{Script}{DefaultLangSys}{FeatureIndex}});
  if (@fidx) {
    @xs = map {
      $xfnt->{GSUB}{FeatureList}{FeatureRecord}[$_]
    } (@fidx);
    foreach (@xs) {
      my $ftag = $_->{FeatureTag}{value};
      my @idx = map { $_->{value} } (@{$_->{Feature}{LookupListIndex}});
      $lidx{$ftag} = \@idx;
    }
  }
  my @xlook = @{$xfnt->{GSUB}{LookupList}{Lookup}};
  foreach my $ftag (sort(keys %lidx)) {
    my %sub; $gsubst{$ftag} = \%sub;
    foreach my $lidx (@{$lidx{$ftag}}) {
      info("scan lookup", $ftag, "index=$lidx");
      my $xlook = $xlook[$lidx];
      if ($xlook->{SingleSubst}) {
        foreach my $x (@{$xlook->{SingleSubst}}) {
          foreach my $xsubst (@{$x->{Substitution}}) {
            $sub{glyphid($xsubst->{in})} = glyphid($xsubst->{out});
          }
        }
      } elsif ($xlook->{LigatureSubst}) {
        foreach my $x (@{$xlook->{LigatureSubst}}) {
          foreach my $xlset (@{$x->{LigatureSet}}) {
            my $g1st = glyphid($xlset->{glyph});
            foreach my $xliga (@{$xlset->{Ligature}}) {
              ($xliga->{glyph} !~ ',') or next;
              my @gfrm = map { glyphid($_) } (split(m/,/, $xliga->{components}));
              $_ = join(',', $g1st, @gfrm);
              $sub{$_} = glyphid($xliga->{glyph});
            }
          }
        }
      } # now skip AlternateSubst
    }
    my @a = keys %sub; $_ = scalar(@a);
    info($ftag, "$_ entires");
  }
  info("analyze done");
}

sub adjust_gsub {
  my ($xfnt) = @_; local ($_); my (@a);
  # vivification
  foreach my $feat (@simpfeat, @compfeat) {
    (exists $gsubst{$feat}) or $gsubst{$feat} = {};
  }

  # glyph width
  my (@gwd);
  my $em = $xfnt->{head}{unitsPerEm}{value};
  info("units per em", $em);
  foreach my $mtx (@{$xfnt->{hmtx}{mtx}}) {
    $gwd[glyphid($mtx->{name})] = $mtx->{width} / $em;
  }

  foreach my $gid (1 .. $#gnames) {
    if ($gwd[$gid] == 1) {
      (exists $gsubst{fwid}{$gid}) or $gsubst{fwid}{$gid} = $gid;
    } elsif ($gwd[$gid] == 0.5) {
      (exists $gsubst{hwid}{$gid}) or $gsubst{hwid}{$gid} = $gid;
    }
  }

  # jp04default
  my $nsjp90 = scalar(keys %{$gsubst{jp90}});
  my $nsjp04 = scalar(keys %{$gsubst{jp04}});
  info("substitution count", "jp90=$nsjp90, jp04=$nsjp04");
  $jp04default = ($nsjp04 < $nsjp90);
  info("default jp-form", (($jp04default) ? 'jp04' : 'jp90'));
  if ($jp04default) {
    foreach my $uc (keys %ucmap) {
      my $g04 = $ucmap{$uc};
      my $g90 = $gsubst{jp90}{$g04};
      if (defined $g90) {
        (exists $gsubst{jp04}{$g90}) or $gsubst{jp04}{$g90} = $g04;
      }
    }
  }

  # ccmp <-> liga
  {
    my ($ccmp, $liga) = ($gsubst{ccmp}, $gsubst{liga});
    foreach my $in (keys %$ccmp) {
      (exists $liga->{$in}) or $liga->{$in} = $ccmp->{$in};
    }
    foreach my $in (keys %$liga) {
      (exists $ccmp->{$in}) or $ccmp->{$in} = $liga->{$in};
    }
  }

  # make idempotent
  foreach my $feat (
    'jp83','jp78','hojo','nlck','trad', 'twid', 'qwid'
  ) {
    my $sub = $gsubst{$feat};
    my @gid = values %$sub;
    foreach my $gid (@gid) {
      (exists $sub->{$gid}) or $sub->{$gid} = $gid;
    }
  }

  # fallback
  foreach my $feat (
    'jp90', 'jp04', 'pwid', 'vert', 'hkna', 'vkna', 'ruby'
  ) {
    my $sub = $gsubst{$feat};
    foreach my $gid (1 .. $#gnames) {
      (exists $sub->{$gid}) or $sub->{$gid} = $gid;
    }
  }
}

sub dump_font {
  if (-f "$in_file$interm_sfx") {
    info("using intermediate file", "$in_file$interm_sfx");
    copy("$in_file$interm_sfx", "$tempb-f.ttx");
  } else {
    my $pfnt = kpse($in_file);
    info("font file path", $pfnt);
    my ($fext) = ($pfnt =~ m/(\.\w+)$/);
    unlink(glob("$tempb-f*.*"));
    copy($pfnt, "$tempb-f$fext") or die;
    info("dump font with TTX...");
    my $yopt = (defined $font_index) ? " -y $font_index" : '';
    my $red = ($verbose) ? '' : "2>$tempb-f2.out";
    system("$ttx$yopt -x post -x glyf -x CFF $tempb-f$fext $red");
    ($? == 0 && -f "$tempb-f.ttx")
      or error("failure in ttx", "$tempb-f$fext");
  }
  info("parse dump data...");
  local $_ = read_whole("$tempb-f.ttx");
  s{(\&\#(\d+);)}{ # purge charrefs invalid in XML
    ($2 < 32 && $2 != 9 && $2 != 10 && $2 != 13) ? '' : $1
  }ge;
  my $xfnt = XMLin($_,
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

#-----------------------------------------------------------

sub generate_cmap {
  my (@bfchar, @bfrange, @cnks);
  my ($scid, $sgid);
  foreach my $cid (0 .. $#gmatch + 1) { # '+ 1' to flush out
    my $gid = $gmatch[$cid];
    (defined $gid && defined $sgid && ($cid & 255) != 0
        && $sgid - $scid == $gid - $cid)
        and next; # in a range
    if (defined $sgid && $scid + 1 == $cid) {
      push(@bfchar, [$scid, $sgid]);
    } elsif (defined $sgid) {
      push(@bfrange, [$scid, $cid - 1, $sgid]);
    }
    ($scid, $sgid) = ($cid, $gid);
  }

  while (@bfchar) {
    my @c = splice(@bfchar, 0, 100);
    push(@cnks, sprintf("%d beginbfchar", scalar(@c)));
    foreach (@c) {
      push(@cnks, sprintf("<%04x> <%04x>", @{$_}));
    }
    push(@cnks, "endbfchar", "");
  }
  while (@bfrange) {
    my @c = splice(@bfrange, 0, 100);
    push(@cnks, sprintf("%d beginbfrange", scalar(@c)));
    foreach (@c) {
      push(@cnks, sprintf("<%04x> <%04x> <%04x>", @{$_}));
    }
    push(@cnks, "endbfrange", "");
  }
  pop(@cnks);

  my $mapping = join("\n", @cnks);
  my ($fnhyph, $fnuscor) = ($psname, $psname); $fnuscor =~ s/-/_/g;
  my $version = sprintf("%.9f", $cmapver); $version =~ s/(\.....*?)0*$/$1/;


  my $cmap = (<<"EOT");
%!PS-Adobe-3.0 Resource-CMap
%%DocumentNeededResources: ProcSet (CIDInit)
%%IncludeResource: ProcSet (CIDInit)
%%BeginResource: CMap (Adobe-Japan1-$fnhyph)
%%Title: (Adobe-Japan1-$fnhyph Adobe Japan1 7)
%%Version: $version
%%EndComments

/CIDInit /ProcSet findresource begin

12 dict begin

begincmap

/CIDSystemInfo 3 dict dup begin
  /Registry (Adobe) def
  /Ordering (Adobe_Japan1_$fnuscor) def
  /Supplement 7 def
end def

/CMapName /Adobe-Japan1-$fnhyph def
/CMapVersion 1.000 def
/CMapType 2 def

/WMode 0 def

1 begincodespacerange
  <0000> <5AFF>
endcodespacerange

$mapping
endcmap
CMapName currentdict /CMap defineresource pop
end
end

%%EndResource
%%EOF
EOT

  (defined $out_file) or $out_file = "Adobe-Japan1-$psname";
  write_whole($out_file, $cmap);
}

sub generate_json {
  my (@map, $scid, $sgid);
  foreach my $cid (0 .. $#gmatch + 1) {
    my $gid = $gmatch[$cid];
    (defined $gid && defined $sgid && $sgid - $scid == $gid - $cid)
        and next; # in a range
    if (defined $sgid && $scid + 1 == $cid) {
      push(@map, [$scid, $sgid]);
    } elsif (defined $sgid) {
      push(@map, [$scid, $cid - 1, $sgid]);
    }
    ($scid, $sgid) = ($cid, $gid);
  }

  my $mapping = join(",\n    ", map {
    '[' . join(", ", @$_) . ']'
  } (@map));
  my $fn = $psname; $fn =~ s/\"/\\\"/g;
  my $ver = sprintf("%.9f", $cmapver); $ver =~ s/(\.....*?)0*$/$1/;

  my $json = (<<"EOT");
{
  "type": "togid",
  "name": "Adobe-Japan1-$fn",
  "version": $ver,
  "mapping": [
    $mapping
  ]
}
EOT

  (defined $out_file) or $out_file = "Adobe-Japan1-$psname.json";
  write_whole($out_file, $json);
}

#-----------------------------------------------------------

sub show_version {
  print("$program $version\n");
}

sub read_option {
  if (!@ARGV) {
    show_usage(); exit;
  }
  my ($arg, @args); local ($_);
  while (@ARGV) {
    $_ = shift(@ARGV);
    if (m/^--$/) {
      last;
    } elsif (m/^-(?:h|-help)$/) {
      show_usage(); exit;
    } elsif (m/^-(?:V|-version)$/) {
      show_version(); exit;
    } elsif (m/^-(?:v|-verbose)$/) {
      $verbose = 1;
    } elsif (m/^-(?:j|-json)$/) {
      $out_json = 1;
    } elsif (m/^--info$/) {
      $out_info = 1;
    } elsif (($arg) = m/^-(?:i|-index)(?:=?(.+))?$/) {
      (defined $arg) or $arg = shift(@ARGV);
      ($arg ne '') or error("missing argument", $_);
      ($arg =~ m/^\d+$/) or error("invalid font index", $arg);
      $font_index = $arg;
    } elsif (($arg) = m/^--cmapver(?:=?(.+))?$/) {
      (defined $arg) or $arg = shift(@ARGV);
      ($arg ne '') or error("missing argument", $_);
      ($arg =~ m/^[\.\d]+$/ && $arg !~ m/\..*\./)
        or error("invalid CMap version", $arg);
      $cmapver = $arg-0;
    } elsif (($arg) = m/^-(?:r|-override)(?:=(.*))?$/) {
      (defined $arg) or $arg = shift(@ARGV);
      ($arg ne '') or error("missing argument", $_);
      $override_file = $arg;
    } elsif (($arg) = m/^-(?:o|-output)(?:=(.*))?$/) {
      (defined $arg) or $arg = shift(@ARGV);
      ($arg ne '') or error("missing argument", $_);
      $out_file = $arg;
    } elsif (m/^-/) {
      error("unknown option", $_);
    } else {
      push(@args, $_);
    }
  }
  splice(@ARGV, 0, 0, @args);
  ($#ARGV == 0) or error("wrong number of arguments");
  ($in_file) = @ARGV;
  if (defined $override_file) {
    (-f $override_file) or error("file not found", $override_file);
  }
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
  ($verbose) and print STDERR (join(": ", $program, @_), "\n");
}
sub error {
  $verbose = 1; info(@_); exit(1);
}

#-----------------------------------------------------------
main();
