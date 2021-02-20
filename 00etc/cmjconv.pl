use strict;
use Encode ('encode', 'decode');
use JSON;
my $program = 'cmjconv';
my $version = '0.2.0';
my $mod_date = '2021/02/10';

# (* = mandatory)
# type: * 'tounicode' / 'togid'
# name: * string
# version: * number
# collection: string
# xuid: array of number
# wmode: number
# codespace: array of array of number
# mapping: array of array of number/string
#   - An element is either a range mapping:
#         [<src_start>, <src_end>, <dst_start>]
#     Or a single-code mapping:
#         [<src>, <dst>]
#   - A number value is converted to a 2-byte string (big-endian).
#     Example: 42 -> <002a>
#   - A string value is encoded in UTF-16BE.
#     Example: "42" -> <00340032>

sub show_usage {
  print(<<"EOT");
This is $program, version $version <$mod_date>
Usage: $program [<option>]... [<cmj-file>]
Reads from stdin when <cmj-file> is omitted.
Writes to stdout when '-o'/'-O' option is absent.
Options:
  -O/--output-file      Write to a file
  -o/--output <file>    Specify output CMap file name
  -v/--verbose          Show more messages
  -h/--help             Show help and exit
  -V/--version          Show version and exit
EOT
}

my $verbose = 0;
my ($in_file, $out_file);

sub main {
  read_option();
  info("input", ((defined $in_file) ? $in_file : "(stdin)"));
  my $cmj = read_whole($in_file);
  my $spec = from_json($cmj);
  validate($spec);
  (defined $out_file && $out_file eq '') and $out_file = $spec->{name};
  info("output", ((defined $out_file) ? $out_file : "(stdout)"));
  imply_tounicode($spec);
  my $cmap = cmap_tounicode($spec);
  write_whole($out_file, $cmap);
}

#-----------------------------------------------------------

sub good_name {
  local ($_) = @_;
  return (m/^[\x21-\x7E]+$/ && !m|[\[\]\(\)\{\}\<\>\/\%\\]|);
}

sub utf16 { # string -> bytes
  return encode('utf-16be', $_[0]);
}

sub hsl { # bytes -> string
  local ($_) = @_; $_ = unpack('H*', $_);
  return "<$_>";
}

sub type {
  my ($v) = @_;
  if (!defined $v) { return 'null'; }
  elsif (ref $v eq 'HASH') { return 'object'; }
  elsif (ref $v eq 'ARRAY') { return 'array'; }
  elsif (JSON::is_bool($v)) { return 'boolean'; }
  elsif ($v =~ m/^[\x20-\x7e]+$/ && ($v ^ $v) eq '0') { return 'number'; }
  else { return 'string'; }
}

sub tonumber { # integer or string -> integer
  local ($_) = @_;
  (type($_) eq 'number') and return $_;
  my $u = utf16($_); my $l = length($u);
  ($l == 2) or error("bad string length ($l)", hsl($u));
  return ord($_);
}

sub toubytes { # integer or string -> bytes
  local ($_) = @_;
  (type($_) eq 'number') or return utf16($_);
  (0 <= $_ && $_ <= 0xFFFF) or error("not in range 0..65535", $_);
  return utf16(chr($_));
}

sub tobytes { # integer or string -> bytes
  local ($_) = @_;
  if (type($_) eq 'number') {
    (0 <= $_ && $_ <= 0xFFFF) or error("not in range 0..65535", $_);
    return pack('n', $_);
  } else {
    my $u = utf16($_); my $l = length($u);
    ($l == 2) or error("bad string length ($l)", hsl($u));
    return $u;
  }
}

sub check_type {
  my ($t, $bv, @idx) = @_;
  my ($v, $vt, $rep) = get_value($bv, @idx);
  (teq($vt, $t)) or error("must be $t ($vt found)", $rep);
}
sub check_type_opt {
  my ($t, $bv, @idx) = @_;
  my ($v, $vt, $rep) = get_value($bv, @idx);
  (teq($vt, $t, 'null')) or error("must be $t ($vt found)", $rep);
}
sub check_type_or {
  my ($t1, $t2, $bv, @idx) = @_;
  my ($v, $vt, $rep) = get_value($bv, @idx);
  (teq($vt, $t1, $t2)) or error("must be $t1 or $t2 ($vt found)", $rep);
}
sub check_array_length {
  my ($min, $max, $bv, @idx) = @_;
  my ($v, $vt, $rep) = get_value($bv, @idx);
  ($vt eq 'array') or error("must be array ($vt found)", $rep);
  my $l = scalar(@$v);
  ($min <= $l && $l <= $max) or error("wrong length ($l)", $rep);
}

sub get_value {
  my ($bv, @idx) = @_; my ($v, $rep) = ($bv, '');
  foreach (@idx) {
    if (type($_) eq 'number') { $v = $v->[$_]; $rep .= "[$_]"; }
    else { $v = $v->{$_}; $rep .= ".$_"; }
  }
  my $vt = type($v);
  ($vt eq 'number' && $v == int($v)) and $vt = 'integer';
  return ($v, $vt, $rep);
}

sub teq {
  my ($vt, @t) = @_;
  foreach (@t) {
    ($vt eq $_ || $vt eq 'integer' && $_ eq 'number') and return 1;
  }
  return 0;
}

#-----------------------------------------------------------

sub validate {
  my ($s) = @_; local ($_);

  # something-something
  if (!defined $s->{name} && defined $in_file) {
    $_ = $in_file; s|^.*/||; s|\.\w+\z||;
    (good_name($_)) or last;
    $s->{name} = $_; info("name is implied", $_);
  }

  # check types
  check_type('string', $s, 'type');
  check_type('string', $s, 'name');
  check_type('number', $s, 'version');
  check_type_opt('string', $s, 'collection');
  check_type_opt('array', $s, 'xuid');
  check_type_opt('integer', $s, 'wmode');
  check_type_opt('array', $s, 'codespace');
  check_type('array', $s, 'mapping');

  if ($s->{xuid}) {
    check_array_length(4, 4, $s, 'xuid');
    foreach my $i (0 .. 3) {
      check_type('integer', $s, 'xuid', $i);
    }
  }

  if ($s->{codespace}) {
    foreach my $i (0 .. $#{$s->{codespace}}) {
      check_array_length(2, 2, $s, 'codespace', $i);
      foreach my $j (0 .. 1) {
        check_type_or('integer', 'string', $s, 'codespace', $i, $j);
      }
    }
  }

  foreach my $i (0 .. $#{$s->{mapping}}) {
    check_array_length(2, 3, $s, 'mapping', $i);
    foreach my $j (0 .. $#{$s->{mapping}[$i]}) {
      check_type_or('integer', 'string', $s, 'mapping', $i, $j);
    }
  }

  $_ = $s->{type};
  (m/^(?:togid|tounicode)$/) or error("invalid type", $_);

  $_ = $s->{name}; (good_name($_)) or error("invalid as PS name", $_);
  if (defined $s->{collection}) {
    $_ = $s->{collection}; (good_name($_)) or error("invalid as PS name", $_);
    my @f = split(m/-/, $_, 3);
    ($f[2] =~ m/^\d+$/) or error("invalid as collection name", $_);
  }
}

my %std_collection = (
  'Adobe-CNS1'   => [7, 0x4AFF],
  'Adobe-GB1'    => [5, 0x76FF],
  'Adobe-Japan1' => [7, 0x5AFF],
  'Adobe-Korea1' => [2, 0x47FF],
  'Adobe-KR'     => [9, 0x59FF],
);

sub imply_tounicode {
  my ($s) = @_; local ($_);
  my $type = $s->{type};

  # collection
  if (!defined $s->{collection}) {
    my ($r, $o, $x) = split(m/-/, $s->{name}, 3);
    $_ = $std_collection{"$r-$o"} || [0]; $x = $_->[0];
    $s->{collection} = $_ = "$r-$o-$x"; info("collection is implied", $_);
  }

  # wmode
  if (!defined $s->{wmode}) {
    $s->{wmode} = $_ = 0; info("wmode implied", $_);
  }

  # codespace
  if (defined $s->{codespace}) {
    ($#{$s->{codespace}} == 0) or error("invalid codespace layout");
    my ($scs, $ecs) = map { tonumber($_) } (@{$s->{codespace}[0]});
    (0 == $scs && $scs <= $ecs && ($ecs & 255) == 255)
      or error("invalid codespace layout");
    @{$s->{codespace}[0]} = (0, $ecs);
  } else {
    my $ecs = 0xFFFF;
    if ($type eq 'togid') {
      my ($r, $o, $s) = split(m/-/, $s->{collection}, 3);
      $_ = $std_collection{"$r-$o"} || [0, 0xFFFF]; $ecs = $_->[1];
    }
    $s->{codespace} = [ [0, $ecs] ]; info("codespace is implied");
  }
  my $ecs = $s->{codespace}[0][1];
  
  foreach my $e (@{$s->{mapping}}) {
    my ($ssc, $esc, $sdc) = @$e;
    (defined $sdc) or ($esc, $sdc) = ($ssc, $esc);
    $ssc = tonumber($ssc); $esc = tonumber($esc);
    ($ssc <= $esc) or error("bad source range", "$ssc..$esc");
    (0 <= $ssc) or error("source codepoint is out of cs", $ssc);
    ($esc <= $ecs) or error("source codepoint is out of cs", $esc);
    $sdc = ($type eq 'tounicode') ? toubytes($sdc) : tonumber($sdc);
    @$e = ($ssc, $esc, $sdc);
  }
}

#-----------------------------------------------------------

sub incr_dc {
  my ($c, $touni) = @_;
  if ($touni) {
    my $k = length($c);
    if ($k == 2) {
      $c = unpack('n', $c) + 1;
      ($c <= 0xFFFF) or error("target codepoint overflow");
      $c = pack('n', $c);
    } else {
      for ($k -= 1; $k >= 0; $k--) {
        my $b = (ord(substr($c, $k, 1)) + 1) % 256;
        substr($c, $k, 1) = chr($b);
        ($b != 0) and last;
      }
      ($k >= 0) or error("target codepoint overflow");
    }
  } else {
    $c += 1; ($c <= 0xFFFF) or error("target codepoint over 65535");
  }
  return $c;
}

sub repr_dc {
  my ($c, $touni) = @_;
  if ($touni) { return hsl($c); }
  else { return sprintf("<%04x>", $c); }
}

sub cmap_tounicode {
  my ($s) = @_; local ($_);
  my ($name, $wmode, $space, $mapping) =
    ($s->{name}, $s->{wmode}, $s->{codespace}, $s->{mapping});
  my $nameh = $name; $nameh =~ s/-/_/g;
  my ($cr, $co, $cs) = split(m/-/, $s->{collection});
  my $touni = ($s->{type} eq 'tounicode');
  my $version = sprintf("%.9f", $s->{version});
  $version =~ s/(\.....*?)0*$/$1/;
  
  my (@rmap, @bfchar, @bfrange);
  foreach my $e (@$mapping) {
    my ($ssc, $esc, $dc) = @$e;
    foreach my $sc ($ssc .. $esc) {
      $rmap[$sc] = $dc; $dc = incr_dc($dc, $touni);
    }
  }
  my ($ssc, $sdc, $edc);
  L1:foreach my $sc (0 .. $#rmap + 1) { # '+ 1' to flush out
    my $dc = $rmap[$sc];
    if (defined $dc && defined $sdc && ($sc & 255) != 0) {
      my $edc1 = incr_dc($edc, $touni);
      if ($edc1 eq $dc) { $edc = $edc1; next L1; }
    }
    if (defined $sdc && $ssc + 1 == $sc) {
      push(@bfchar, [$ssc, $sdc]);
    } elsif (defined $sdc) {
      push(@bfrange, [$ssc, $sc - 1, $sdc]);
    }
    ($ssc, $sdc, $edc) = ($sc, $dc, $dc);
  }

  my @cnks = (sprintf('%d begincodespacerange', scalar(@$space)));
  foreach my $e (@$space) {
    push(@cnks, sprintf("  <%04X> <%04X>", @$e));
  }
  push(@cnks, 'endcodespacerange', '');

  while (@bfchar) {
    my @c = splice(@bfchar, 0, 100);
    push(@cnks, sprintf("%d beginbfchar", scalar(@c)));
    foreach my $e (@c) {
      my ($sc, $dc) = @$e; $dc = repr_dc($dc, $touni);
      push(@cnks, sprintf("<%04x> %s", $sc, $dc));
    }
    push(@cnks, "endbfchar", "");
  }
  while (@bfrange) {
    my @c = splice(@bfrange, 0, 100);
    push(@cnks, sprintf("%d beginbfrange", scalar(@c)));
    foreach my $e (@c) {
      my ($ssc, $esc, $dc) = @$e; $dc = repr_dc($dc, $touni);
      push(@cnks, sprintf("<%04x> <%04x> %s", $ssc, $esc, $dc));
    }
    push(@cnks, "endbfrange", "");
  }

  pop(@cnks);
  my $mapentry = join("\n", @cnks);

  return (<<"EOT");
%!PS-Adobe-3.0 Resource-CMap
%%DocumentNeededResources: ProcSet (CIDInit)
%%IncludeResource: ProcSet (CIDInit)
%%BeginResource: CMap ($name)
%%Title: ($name $cr $co $cs)
%%Version: $version
%%EndComments

/CIDInit /ProcSet findresource begin

12 dict begin

begincmap

/CIDSystemInfo 3 dict dup begin
  /Registry ($cr) def
  /Ordering ($nameh) def
  /Supplement $cs def
end def

/CMapName /$name def
/CMapVersion $version def
/CMapType 2 def

/WMode $wmode def

$mapentry
endcmap
CMapName currentdict /CMap defineresource pop
end
end

%%EndResource
%%EOF
EOT
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
    } elsif (($arg) = m/^-(?:o|-output)(?:=(.*))?$/) {
      (defined $arg) or $arg = shift(@ARGV);
      ($arg ne '') or error("missing argument", $_);
      $out_file = $arg;
    } elsif (m/^-(?:O|-output-file)$/) {
      $out_file = '';
    } elsif (m/^-/) {
      error("unknown option", $_);
    } else {
      push(@args, $_);
    }
  }
  splice(@ARGV, 0, 0, @args);
  ($#ARGV <= 0) or error("wrong number of arguments");
  ($in_file) = @ARGV;
}

sub read_whole {
  my ($p) = @_; local ($_, $/);
  if (defined $p) {
    open(my $h, '<', $p) or error("caanot open for read", $p);
    binmode($h); $_ = <$h>;
    close($h);
  } else { # stdin
    binmode(STDIN); $_ = <STDIN>;
  }
  return decode('utf-8', $_);
}
sub write_whole {
  my ($p, $d) = @_; local ($_);
  if (defined $p) {
    open(my $h, '>', $p) or error("caanot open for write", $p);
    binmode($h); print $h ($d);
    close($h);
  } else {
    binmode(STDOUT); print($d);
  }
}

sub kpse {
  my ($f) = @_;
  local $_ = `kpsewhich $f`; chomp($_);
  return ($_ eq '') ? undef : $_;
}

sub info {
  ($verbose) and print STDERR (join(": ", $program, @_), "\n");
}
sub error {
  $verbose = 1; info(@_); exit(1);
}

#-----------------------------------------------------------
main();
