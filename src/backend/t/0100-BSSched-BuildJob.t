use strict;
use warnings;

use Test::More tests => 22;
use Data::Dumper;
use feature qw/say/;

require_ok('BSSched::BuildJob');


my ($got,$expected,$fixture);

################################################################################
my @basefile = split('/',__FILE__);
my $basename = pop(@basefile);
my $dirname  = join('/',@basefile);

$BSConfig::bsdir = $dirname . "/tmp/0006";
unlink($BSConfig::bsdir);
$BSSched::arch = 'x86_64';
$BSSched::reporoot = $dirname . "/tmp/0006/build";
my $prp           = 'openSUSE:Test/standard';
my $packid        = 'kernel';
my $fdir          = join('/',$BSSched::reporoot,$prp,$BSSched::arch);
my $pkg_finished  = join('/',$fdir,':packstatus.finished');
my $gctx	  = {
	reporoot => $dirname . "/tmp/0006/build",
	arch	 => 'x86_64' 
};

BSUtil::mkdir_p($fdir);
unlink $pkg_finished;
BSUtil::touch($pkg_finished);
# 
BSSched::BuildJob::patchpackstatus($gctx,'openSUSE:Test/standard','kernel','building');
my $content =  get_file_content($pkg_finished);
is_deeply($content,["building kernel\n"],'Checking content in packstatus.finished');
#
BSSched::BuildJob::patchpackstatus($gctx,'openSUSE:Test/standard','kernel');
$content =  get_file_content($pkg_finished);
is_deeply(
  $content,
  ["building kernel\n","unknown kernel\n"],
  'Checking content in packstatus.finished'
);

################################################################################

my $changes = BSSched::BuildJob::sortedmd5toreason('!a','+b','-c');
my @r = (
  {key=>'a',change=>'md5sum'},
  {key=>'b',change=>'added'},
  {key=>'c',change=>'removed'}
);
for my $got (@$changes) {
  my $expected = shift(@r);
  is_deeply($got,$expected,"Checking sortedmd5toreason" );
};

################################################################################
$fixture = [
  {},
  {
  path => [
    { path => 'abc' , project => 'openSUSE:Factory' , repository => 'standard' },
  ],
  },
];

@$got = BSSched::BuildJob::expandkiwipath(@$fixture);
$expected = [ 'openSUSE:Factory/standard' ];
is_deeply($got,$expected,'Checking testcase 1 TODO: better description');
################################################################################
$fixture = [
    {
      prpsearchpath => ['prpsearchpath1','prpsearchpath2']
    },
    {
      path => [
        { path => 'abc' , project => '_obsrepositories' },
      ],
    },
];
@$got = BSSched::BuildJob::expandkiwipath(@$fixture);
$expected = [ 'prpsearchpath1', 'prpsearchpath2' ];
is_deeply($got,$expected,'Checking with _obsrepositories and prpsearchpath');

################################################################################
$fixture = [
    {},
    {
      path => [
        { path => 'abc' , project => '_obsrepositories' },
      ],
    },
];
@$got = BSSched::BuildJob::expandkiwipath({}, @$fixture);
$expected = [];
is_deeply($got,$expected,'Checking with _obsrepositories w/o prpsearchpath');
################################################################################
@$got = BSSched::BuildJob::expandkiwipath({});
is_deeply($got,[],'Checking empty $info->{path} element');

### Testing BSSched::BuildJob::jobname
$got= BSSched::BuildJob::jobname("openSUSE:Factory/standard","kernel");
is($got,'openSUSE:Factory::standard::kernel',"Checking jobname normal length");
################################################################################
$got= BSSched::BuildJob::jobname("openSUSE:Factory/standard","kernel". ( "x" x 200 ));
is($got,':cc9039e0510bfb4c513ff8c0f8360cab:::eb57b075a7e17391136eff38c63547e4',"Checking jobname oversized packid");
################################################################################
$got= BSSched::BuildJob::jobname("openSUSE:Factory/standard" . ( "x" x 200 ),"kernel");
is($got,':7f34cc064ad26bb6433937dee6e058b6::kernel',"Checking jobname oversized prp");
################################################################################
# Testing Global Build ID Tracking & Migration on Read
################################################################################
use File::Path qw(remove_tree);

# Setup mock directories
my $test_bsdir = $dirname . "/tmp/0100_global_bcnt";
$BSConfig::bsdir = $test_bsdir;
remove_tree($test_bsdir) if -d $test_bsdir;

my $test_projid = "P1";
my $test_packid = "A1";
my $versrel = "1.0-1";

my $ctx = {
  'project' => $test_projid,
  'gdst' => "$test_bsdir/build/$test_projid/standard/x86_64",
};
my $dst = "$ctx->{'gdst'}/$test_packid";
my $pdata = {
  'versrel' => $versrel,
};

# 1. Test nextbcnt with empty history (should return 1)
my $bcnt = BSSched::BuildJob::nextbcnt($ctx, $test_packid, $pdata);
is($bcnt, 1, "nextbcnt returns 1 with no history");

# 2. Test addsucceededhist writes to both local and global history
my $info = {
  'project' => $test_projid,
  'package' => $test_packid,
  'versrel' => $versrel,
  'bcnt' => 1,
  'srcmd5' => '12345',
  'rev' => '1',
  'reason' => 'test build',
};
my $now = time();
BSUtil::mkdir_p($dst);
BSSched::BuildJob::addsucceededhist($dst, $info, $now, 42);

# Verify local history exists
ok(-f "$dst/history", "addsucceededhist writes local history");

# Verify global history exists
my $global_history_dir = "$test_bsdir/db/buildcounter/$test_projid/$test_packid";
ok(-f "$global_history_dir/history", "addsucceededhist writes global history");

# 3. Test nextbcnt reads from global history and increments (should return 2)
$bcnt = BSSched::BuildJob::nextbcnt($ctx, $test_packid, $pdata);
is($bcnt, 2, "nextbcnt reads from global and increments build counter");

# 4. Test Migrate-on-Read:
# Clear global history, keep local history
remove_tree($global_history_dir);
ok(!-d $global_history_dir, "Removed global history for migrate-on-read test");

# Call nextbcnt (should trigger migration from local to global, and return 2)
$bcnt = BSSched::BuildJob::nextbcnt($ctx, $test_packid, $pdata);
is($bcnt, 2, "nextbcnt migrates local history to global on read and returns 2");
ok(-f "$global_history_dir/history", "Migration successfully created global history");

# 5. Test persistence across project/repository deletion:
# Succeeded build is already recorded. Now simulate a complete repository/project wipe:
remove_tree($ctx->{'gdst'});
ok(!-d $ctx->{'gdst'}, "Entire repository/project directory was completely deleted");

# Call nextbcnt (should still find history in the global store and return 2)
$bcnt = BSSched::BuildJob::nextbcnt($ctx, $test_packid, $pdata);
is($bcnt, 2, "nextbcnt persists and returns 2 even after the project repository directory is deleted");

remove_tree($test_bsdir) if -d $test_bsdir;
################################################################################

exit 0;
sub get_file_content {
  my ($file) = @_;
  open(FH,"< $file") or die $!;
  my @content = <FH>;
  close(FH);
  return \@content
}


