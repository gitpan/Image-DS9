use inc::Module::Install;

name	'Image-DS9';
all_from 'DS9.pm';

requires 'IPC::XPA' => '0.08';
test_requires Test::More => '0.31';
requires_external_bin 'ds9';

WriteAll;
