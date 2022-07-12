#!/usr/bin/perl

use strict;
use Cwd;
use Getopt::Long;


use IPC::Open3;
use Symbol qw(gensym);
use IO::File;

# setup options;
# Ignore args with no options (eg, the list of files)
$Getopt::Long::passthrough = 1;  
# Be case sensitive
$Getopt::Long::ignorecase = 0;
my $options = { };
GetOptions($options, "-H", "-help", "--help", "-config:s","-logfile:s", "-filelimit:s","-debug", "-cleanup","-imcleanup","-archive_dat","-delete_dat");
my $USAGE = qq~
Usage:
        flyem_dat_transfer_convert2_png.pl <Optional parameter files>
        
        This script will log into Hess Lab's Feiss PC and transfer .dat files and convert them to png for image stack alignment.

        Example: flyem_dat_transfer_convert2_png.pl

        Set parameter files (optional):
                -config     specify a configuration file to use to connect to bowl PCs. Otherwise it will use default config.
                -logfile    specify a custom log file to write out to.
                -debug      will execute script but not transfer or delete source data.
                -cleanup    will remove flag file off of data collection PC
                -imcleanup  will delete files off of source after transfer
                -archive_dat    will archive .dat file to /nearline/flyem/data
                -delete_dat     will delete .dat file
~;

if ( $options->{'H'} || $options->{'-help'} || $options->{'help'}) {
        print $USAGE;
        exit 0;
}

#default config
my $config = "/groups/flyem/home/flyem/bin/dat_transfer/flyem_dat_transfer_convert2_png.config";

$config = $options->{'config'} if ($options->{'config'});
my $rh_Box_Info = parseConfig($config);

transfer_data($rh_Box_Info);

exit;
# subroutines
sub transfer_data {
        my ($rh_Box_Info) = @_;
	my $log_file = "flyem_dat_transfer_convert2_png.log";
	$log_file = $options->{'logfile'} if ($options->{'logfile'});
	
	my $report = "The following directories have been transferred to directory /groups/flyem/data/\n";
	open (LOG,">>$log_file") || die "Can not open $log_file for writing\n";
	my $files_count = 0;

	foreach my $id (sort numerically keys %$rh_Box_Info) {
		my ($hostname, $ip, $source_dir, $copy_to_dir, $archive_to_dir);
		$hostname = $$rh_Box_Info{$id}->{'hostname'};
		$ip = $$rh_Box_Info{$id}->{'ip'};
		$source_dir = $$rh_Box_Info{$id}->{'source_dir'};
		$copy_to_dir = $$rh_Box_Info{$id}->{'copy_to_dir'};
		$archive_to_dir = $$rh_Box_Info{$id}->{'archive_to_dir'};

		#print "$copy_to_dir\n";		
                my $now_string = localtime;
		print "$now_string : Transferring directores on $hostname $ip\n";
		$report .= "Files transferred from $hostname: \"$source_dir\" to \"$copy_to_dir\"\n";
		
		my $rh_existing_dir_lookup = get_existing_dirs($copy_to_dir);
	        #foreach my $exdir (sort keys %$rh_existing_dir_lookup) {print "$exdir\n";}
	    
		my $ar_fly_o_dirs = ssh_list_dir($ip,$source_dir);
		my $copy_count = 0;
		my $scp_cmd = "scp -o ConnectTimeout=1800 -o StrictHostKeyChecking=no -r $ip:'"; 
		#my $scp_cmd = "rsync -avh --ignore-existing -r $ip:'";
		my $dat_copy_path;

		foreach my $transfer_dir (@$ar_fly_o_dirs) {
		    
		    if (exists($$rh_existing_dir_lookup{$transfer_dir})) {
			# existing directory
			# don't do anything.... yet!
			# print "Found $transfer_dir\n";
		    } else {
			my $target_data = $transfer_dir;
			$target_data =~ s/\015//;
			my $new_dir_name;
			print "T: $transfer_dir\n";
			print "Target: $target_data\n";
			my @tdata1 = split(/\^\^/,$target_data);				
			my @parse_drive = split(/\^/,$tdata1[0]);
				
			my $drive = lc(pop(@parse_drive));

			my $project_dir_name = $parse_drive[0];
			my $project_dir_path = "$copy_to_dir/$project_dir_name";
			unless(-e $project_dir_path) {
			    mkdir("$project_dir_path");
			}
			$dat_copy_path = "$project_dir_path/dat";
			unless(-e $dat_copy_path) {
			    print "Here $dat_copy_path\n";
			    mkdir("$dat_copy_path");
			    chmod(0755,$dat_copy_path);			    
			}
			
			my $inlens_path = "$project_dir_path/InLens";
			unless(-e $inlens_path) {
			    mkdir("$inlens_path");
			}
			
			my $rlogs = "$project_dir_path/runlogs";
			unless(-e $rlogs) {
			    mkdir("$rlogs");
			}
			
			my $logs = "$project_dir_path/logs";
			unless(-e $logs) {
			    mkdir("$logs");
			}
			
			my $tmp_path = "$project_dir_path/tempdat";
				#$copy_count;
			unless(-e $tmp_path) {
			    #mkdir("$tmp_path");
			}
			my $raw_path = "$project_dir_path/raw";
			unless(-e $raw_path) {
			    #mkdir("$raw_path");
			}
				
			my $archive_path = $archive_to_dir . "/" . $project_dir_name;
			my $archive_dat_path = "$archive_path/dat";
			if ($options->{'archive_dat'}) { 
			    unless (-e $archive_path) {
				mkdir("$archive_path");
			    }
			    unless (-e $archive_dat_path) {
				mkdir("$archive_dat_path");
			    }
			}
			
			my $datfile = $tdata1[1];
			
			$datfile =~ s/\^/\//g;
			
			my $datfile_path = "/cygdrive/$drive/$datfile";
			
			my @path_components = split(/\//,$datfile_path);
			my $del_flag = pop(@path_components);
			$datfile_path = join("/",@path_components);
			
			my $datfile_name = pop(@path_components);
			
			print "Drive: $drive $datfile_name\n";
			
			#my $tif_filename = $datfile_name;
			#$tif_filename =~ s/\.dat//;
			#$tif_filename =  $tif_filename . "_InLens.tif";
			
			$scp_cmd .= "\"$datfile_path\" ";
			$files_count++;
		    }
		}

		$scp_cmd .= "' \"$dat_copy_path/\"";
		my $chmod = "chmod 644 $dat_copy_path/*";
		my $rc = 0;

		if ($options->{'debug'}) {
		    print "SCP: $scp_cmd\n";
		    print "CHMOD: $chmod\n";
		} else {
		    if ($files_count) {
                        my $now_string = localtime;
			print "$now_string : Transferring $scp_cmd\n";
			eval {			
			    local $SIG{'ALRM'} = sub { die "alarm\n"; };
			    alarm(600);
			    $rc = system($scp_cmd);
                            my $now_string = localtime;
			    print "$now_string : SCP Return Code: $rc\n";
			    print "run $chmod\n";
			    system($chmod);
			    alarm(0);
			};
			if ($@) {
			    #die unless $@ eq "alarm\n"; # propagate unexpected errors
			    print "Timeout Error SCP transfer of dat files took longer than 10 minutes\n";
			    # timed out
			    #exit(0);
	                    die(1)
			}
		    } else {
			print "No images flagged to transfer\n";
		    }
		}

		my $rm_flagfile = "ssh $ip -o StrictHostKeyChecking=no 'rm -f ";
		my $rm_datfile = "ssh $ip -o StrictHostKeyChecking=no 'rm -f ";
		my $dats_to_delete = 0;
		my $flags_to_delete = 0;
		foreach my $transfer_dir (@$ar_fly_o_dirs) {
		    my $target_data = $transfer_dir;
		    $target_data =~ s/\015//;
		    my $new_dir_name;
		    print "T: $transfer_dir\n";
		    print "Target: $target_data\n";
		    my @tdata1 = split(/\^\^/,$target_data);
		    my @parse_drive = split(/\^/,$tdata1[0]);
		    my $drive = lc(pop(@parse_drive));
		    my $project_dir_name = $parse_drive[0];
		    my $project_dir_path = "$copy_to_dir/$project_dir_name";
		    
		    my $dat_copy_path = "$project_dir_path/dat";
		    
		    my $inlens_path = "$project_dir_path/InLens";
		    
		    my $rlogs = "$project_dir_path/runlogs";
		    
		    my $logs = "$project_dir_path/logs";

		    # not sure if needed anymore
		    my $tmp_path = "$project_dir_path/tempdat";		    
		    my $raw_path = "$project_dir_path/raw";
		    
		    my $archive_path = $archive_to_dir . "/" . $project_dir_name;
		    my $archive_dat_path = "$archive_path/dat";
		    
		    my $datfile = $tdata1[1];

		    $datfile =~ s/\^/\//g;

		    my $datfile_path = "/cygdrive/$drive/$datfile";

		    my @path_components = split(/\//,$datfile_path);
		    my $del_flag = pop(@path_components);
		    $datfile_path = join("/",@path_components);

		    my $datfile_name = pop(@path_components);

		    print "Drive: $drive $datfile_name\n";
		    
		    if ($rc == 0) {
			$copy_count++;
			# succesful transfers
			print "Successful Transfer\n";
			print LOG "$hostname\t$ip\t$datfile_path\t$dat_copy_path/$datfile_name\n";
			
			$report .= "$dat_copy_path/$datfile_name Transfer Successful\n";
			
			# convert to png
			my $sh_commands = "";
			my $convert_dat_to_png = "/groups/flyem/home/flyem/bin/compress_dats/Compress dat/$datfile_name 0 InLens logs -N $copy_count";
			$sh_commands .= "$convert_dat_to_png;\n";
			if ($options->{'delete_dat'}) {
			    $sh_commands .= "rm $dat_copy_path/$datfile_name;\n";
			}

			if ($options->{'archive_dat'}) {
			     $sh_commands .= "rm $dat_copy_path/$datfile_name;\n";
			 }
			my $pid = int(rand(50000));
			my $shfile = "$project_dir_path/convert_" . $copy_count . "_" . $pid .".sh";
			
			$sh_commands .= "rm $shfile;\n";
			
			open(OUT,">$shfile") || die "cant open $shfile\n";
			print OUT qq~\#!/bin/bash
$sh_commands
~;
			close(OUT);
			chmod(0755,$shfile);
			 if ($options->{'archive_dat'}) {
			     my $copy_dat_file_archive = "cp \"$dat_copy_path/$datfile_name\" \"$archive_dat_path/$datfile_name\"";
			     #print "Archiving: $copy_dat_file_archive\n";
			     system($copy_dat_file_archive);
			     #my $rm_dat_cmd = "rm \"$dat_copy_path/$datfile_name\"";
			     #print "Deleting: $rm_dat_cmd\n";
			     #system($rm_dat_cmd);
			 }	
			
			if ($options->{'debug'}) {
			    print "Convert dat to png: $convert_dat_to_png\n";
			} else {
			    chdir("$project_dir_path");
			    my $r = $datfile_name;
			    $r =~ s/\.dat//;
			    my $bsub_cmd = "bsub -W 59 -J pp.$copy_count.$pid -o runlogs/$r.stdout -e runlogs/$r.stderr -P flyem -n 1 $shfile";
			    print "$bsub_cmd\n";
			    system($bsub_cmd);
			    chdir("/groups/flyem/home/flyem/bin/dat_transfer");
			}

			
			if ($options->{'cleanup'}) {
			    # remove dir
			    print "Removing $ip $source_dir" . "$target_data\n";
			    #$target_data =~ s/\015//;
			    $rm_flagfile .= " \"$source_dir" . "$target_data\" ";
			    $flags_to_delete++;			    
			    # if keep do not delete if delete remove dat file
			    #my $rm_this_flagfile = "ssh $ip 'rm -f " . "\"$source_dir" . "$target_data\"'";
			    #if ($options->{'debug'}) {
				#print "debug: $rm_this_flagfile";
				#print "$rm_flagfile\n";
				#print "flag:$del_flag cmd:$rm_datfile\n";
			    #} else {
				#print "remove this flagfile: $rm_this_flagfile\n";
				#system($rm_this_flagfile);
				#print "flag file deletion done\n";
			    #}
	
			    if ($del_flag eq "delete") {
				$dats_to_delete++;
				$rm_datfile .= "\"$datfile_path\" ";
			    } else {
				print "flag: $del_flag . Keep dat file\n";
			    }
			    #}
			}
		    } else {
			$report .= "$source_dir/$transfer_dir FAILED\n";
			my $rmcopydir = "rm -f \"$dat_copy_path/$datfile_name\"";
			system($rmcopydir);
		    }
		    		
		}

		$rm_flagfile .= "'";
		$rm_datfile .= "'";
		
		if ($flags_to_delete > 0) {
		
		    if ($options->{'debug'}) {
			print "delete flag files $rm_flagfile\n";
		    } elsif ($options->{'cleanup'}) {		    
			eval {
			    local $SIG{'ALRM'} = sub { die "alarm\n"; };
			    alarm(120);
			    print "exec $rm_flagfile \n";
			    system($rm_flagfile);
			    alarm(0);
			};
			if ($@) {
			    #die unless $@ eq "alarm\n"; # propagate unexpected errors
			    print "Timeout Error for SSH deletion of flag file\n";
			    # timed out
			    exit(0);
			}
		    } else {
			print "No flag files deleted\n";
		    }
		}

		
		if ($dats_to_delete > 0) {		
		    if ($options->{'debug'}) {
			print "delete dat files $rm_datfile\n";
		    } elsif ($options->{'cleanup'}) {
			eval {
			    local $SIG{'ALRM'} = sub { die "alarm\n"; };
			    alarm(120);
			    print "exec $rm_datfile\n";
			    system($rm_datfile);
			    alarm(0);
			};
			if ($@) {
			    print "Timeout Error for SSH deletion of dat file\n";
			    # timed out
			    exit();
			}
		    } else {
			print "Keep dat files\n";
		    }
		} else {
		    print "no dats marked for deletion\n";
		}
		
		if ($copy_count < 1) {
		    $report .= "No Data Transferred\n";
		}
				
		print "\n";
        }
	close (LOG);
}

sub get_existing_dirs {
	my ($copy_to_dir) = @_;
	
	my %existing_dir_lookup;
	opendir ( DIR, "$copy_to_dir" ) || die "Error in opening copy dir $copy_to_dir\n";
	while( (my $existing_dir = readdir(DIR))){
		next if ($existing_dir =~ /^\./);
		#print 	"$existing_dir\n";	
		$existing_dir_lookup{$existing_dir} = $existing_dir;
	}
	closedir (DIR);

	return (\%existing_dir_lookup);
}

sub ssh_list_dir {
	my ($ip,$source_dir) = @_;
	my @fly_o_dirs = ();
	my $cmd = "ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -o ServerAliveInterval=5 $ip 'ls $source_dir'";
	#if ($options->{'filelimit'}) {
	    #my $filelimit = $options->{'filelimit'};
	    #$cmd = "ssh $ip 'ls $source_dir | head -n $filelimit'";
	#}

	print "$cmd\n";

	eval {
	    local $SIG{'ALRM'} = sub { die "alarm\n"; };
	    alarm(360);
	    open(CMD,"$cmd |");
	    my $filecount = 0;
	    while (my $line = <CMD>) {
		chomp($line);
		$line =~ s/\R//;
		next if ($line =~ /^\./);
		if ($line =~ /\.dat/) {
		    $filecount++;
		    if ($options->{'filelimit'}) {
			if ($filecount <= $options->{'filelimit'}) {
			    print "$line\n";
			    push(@fly_o_dirs,$line);
			} else {
			    last;
			}
		    } else {
			print "$line\n";
			push(@fly_o_dirs,$line);
		    }

		}
		
	    }
	    close(CMD);
	    alarm(0);
	};
	my $cmd_exit_code = $?;
	if ($cmd_exit_code != 0) {
	  print "ssh_list_dir command exit code is $cmd_exit_code\n";
	  die(1)
	}
	if ($@) {
	    #die unless $@ eq "alarm\n"; # propagate unexpected errors
	    print "Timeout Error for SSH listing of files\n";
	    # timed out
	    exit();
	}
	return(\@fly_o_dirs);
}

sub parseConfig {
	my ($config) = @_;
	my %Box_Info;
	open(IN,"$config") || die "Can not open $config\n";
	my $id = 1;
	while (my $line = <IN>) {
		next if ($line =~ /^\#/);
		chomp($line);
		#print "$line\n";
		my ($hostname,$ip,$source_dir,$copy_to_dir,$archive_to_dir) = split(/\t/,$line);
		$Box_Info{$id}->{'hostname'} = $hostname;
		$Box_Info{$id}->{'ip'} = $ip;
		$Box_Info{$id}->{'source_dir'} = $source_dir;
		$Box_Info{$id}->{'copy_to_dir'} = $copy_to_dir;
		$Box_Info{$id}->{'archive_to_dir'} = $archive_to_dir;
		$id++;
	}
	
	close(IN);
	return (\%Box_Info)
}

sub numerically {
	$a <=> $b;
}

