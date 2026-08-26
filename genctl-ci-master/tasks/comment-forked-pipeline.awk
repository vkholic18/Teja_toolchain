#============================================================
#
#   comment-forked-pipeline.awk -- prepare forked pipeline to run without tainting the public build
#-------------------------------
#  usage: awk -f /genesis/comment-forked-pipeline.awk -v fork_comment='FORK-COMMENTED' -v fork_owner='FORK-OWNER-USERID' monitoring.yaml
#
#		To test it, append this:  | grep 'USERID\|FORK-COMMENTED'
#============================================================
BEGIN {
	if (fork_comment=="")
		fork_comment = "FORK-COMMENTED"
	if (fork_owner=="")
	   fork_owner   = "FORK-OWNER-USERID"
}
//{
	line = $0
	if (reverse)
	{
		#print "REVERSE!!"
		if (index(line, "repository:")==0)
			sub(fork_owner, "genctl")

		if (index(line, fork_comment) > 0)
			sub(/^\# /, "")
	}
	else
	{
		if (index(line, "repository:")==0)
			sub(/genctl\//, fork_owner"/")

		if (index(line, fork_comment) > 0)
			sub(/^/, "# ")
	}
	print
}
