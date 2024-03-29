use 5.008001;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'SignalWire::ML',
    VERSION_FROM      => 'lib/SignalWire/ML.pm', # finds $VERSION
    PREREQ_PM         => { YAML::PP => "0.38.0" }, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (AUTHOR         => 'Brian West <brian@signalwire.com>') : ()),
);
