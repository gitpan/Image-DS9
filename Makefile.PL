use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'	=> 'Image::DS9',
    'VERSION_FROM' => 'DS9.pm', # finds $VERSION
    'PREREQ_PM' => { IPC::XPA => 0,
		     Test::More => 0,
		   },
);
