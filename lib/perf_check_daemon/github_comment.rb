
require "optparse"
require "shellwords"

class GithubComment
  def self.extract_jobs(issue, object)
    jobs = []

    job_template = {
      issue:          issue.fetch('url'),
      issue_title:    issue.fetch('title'),
      issue_html_url: issue.fetch('html_url'),
      issue_comments: issue.fetch('comments_url'),
      github_holder:  object
    }

    if issue["head"]
      job_template.merge!(
        branch:         issue.fetch('head').fetch('ref'),
        reference:      issue.fetch('base').fetch('ref'),
        sha:            issue.fetch('head').fetch('sha'),
        reference_sha:  issue.fetch('base').fetch('sha'),
      )
    else
      # For regular issues, default to master-master
      # SHA is currently only used for gist naming,
      # so it's okay to be imprecise in this case
      job_template.merge!(
        branch:         "master",
        reference:      "master",
        sha:            "master",
        reference_sha:  "master"
      )
    end

    object.fetch('body').scan(/^@#{github.user} (.+)/).each do |args|
      job = job_template.dup
      branch, args = parse_branch(args.first)
      job[:arguments] = args

      if branch
        job[:branch] = branch
        job[:sha] = branch
      end

      jobs.push(job)
    end

    jobs
  end

  # Extract --branch XYZ pseudo-option from mentions
  def self.parse_branch(args)
    branch = nil

    args = Shellwords.shellsplit(args)
    args[0..-1].each_with_index do |arg, iarg|
      if arg == "--branch"
        branch = args[iarg+1]
        args.delete_at(iarg+1)
        args.delete_at(iarg)
        break
      end
    end

    [branch, Shellwords.shelljoin(args)]
  end
end
