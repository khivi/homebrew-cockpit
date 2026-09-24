# Homebrew formula for cockpit — cmux/limux workspaces backed by git worktrees.
#
# Install:  brew tap khivi/cockpit && brew install cockpit
# Update:   brew upgrade cockpit
# Works on macOS and Linux (Linuxbrew) — cockpit is pure Python (Textual TUI).
#
# MAINTENANCE:
#   - `url` + `sha256` are bumped automatically by the cockpit repo's release CI
#     (.github/workflows/release.yml) on every `v*` tag — do not hand-edit them.
#   - The `resource` blocks (Textual + its transitive deps) change only when a
#     dependency version moves. Regenerate then with:
#       brew update-python-resources Formula/cockpit.rb
#     A block may sit a release or two behind PyPI's latest on purpose: nothing
#     here is adopted until it has been public for the 7 days
#     .github/dependabot.yml applies to every other pin in this repo, since a
#     compromised release is usually yanked within days. Being behind is not a
#     missed regeneration — check the upload date before "fixing" it.
#   - `sha256` below is a placeholder until the first `v*` tag is pushed; the
#     CI fills it in on that release.
class Cockpit < Formula
  include Language::Python::Virtualenv

  desc "Git-worktree workspaces for cmux/limux, aligned to GitHub PRs"
  homepage "https://github.com/khivi/cockpit"
  url "https://github.com/khivi/cockpit/archive/refs/tags/v3.8.1.tar.gz"
  sha256 "5e0571348dc24c680733edc4ae7782dac7b177194c89ff24bacdb23755a59540"
  license "MIT"

  depends_on "gh"
  depends_on "python@3.12"

  resource "textual" do
    url "https://files.pythonhosted.org/packages/00/21/39a76b01bd5eea82a04baaca7580e105d8c59450df03998345bb2cfb307b/textual-8.2.8.tar.gz"
    sha256 "3f106a9fbc73e39dd266c9712432087de78a6d644084c7c241d6a25c3169115b"
  end

  resource "rich" do
    url "https://files.pythonhosted.org/packages/c0/8f/0722ca900cc807c13a6a0c696dacf35430f72e0ec571c4275d2371fca3e9/rich-15.0.0.tar.gz"
    sha256 "edd07a4824c6b40189fb7ac9bc4c52536e9780fbbfbddf6f1e2502c31b068c36"
  end

  resource "markdown-it-py" do
    url "https://files.pythonhosted.org/packages/06/ff/7841249c247aa650a76b9ee4bbaeae59370dc8bfd2f6c01f3630c35eb134/markdown_it_py-4.2.0.tar.gz"
    sha256 "04a21681d6fbb623de53f6f364d352309d4094dd4194040a10fd51833e418d49"
  end

  resource "mdurl" do
    url "https://files.pythonhosted.org/packages/d6/54/cfe61301667036ec958cb99bd3efefba235e65cdeb9c84d24a8293ba1d90/mdurl-0.1.2.tar.gz"
    sha256 "bb413d29f5eea38f31dd4754dd7377d4465116fb207585f97bf925588687c1ba"
  end

  resource "linkify-it-py" do
    url "https://files.pythonhosted.org/packages/45/98/7a1a5f31fd5c7ba93e963b168e244b8e3dd705b3d2a718e3c3307583bf57/linkify_it_py-2.2.0.tar.gz"
    sha256 "907acd2d17ac1fbb9ddb62c8957ccbd6158cac602231a15c3b0cd1e215f03cee"
  end

  resource "mdit-py-plugins" do
    url "https://files.pythonhosted.org/packages/59/fc/f8d0863f8862f25602c0404d75568e89fb6b4109804645e5cdfb1be5cf56/mdit_py_plugins-0.6.1.tar.gz"
    sha256 "a2bca0f039f39dbd35fb74ae1b5f998608c437463371f0ff7f49a19a17a114d0"
  end

  resource "platformdirs" do
    url "https://files.pythonhosted.org/packages/53/18/f3bb8ef0d3b930692343da8aa4d3cbcd6749477c053959395ac81965a6e9/platformdirs-4.11.8.tar.gz"
    sha256 "f23abafea7dd4276d1f29104b83598d7dcc567cafd07c9c951e66665645437fc"
  end

  resource "Pygments" do
    url "https://files.pythonhosted.org/packages/49/2e/ced460408999b33da6b31b0021b0f37d329e202d4169aeb164493778f25b/pygments-2.21.0.tar.gz"
    sha256 "610ca751c9bc2492b38eb9a38a7fbc93edbbb2d7182edaf34e66ae493dee5c8c"
  end

  resource "typing-extensions" do
    url "https://files.pythonhosted.org/packages/f6/cc/6253133b5bb138fc3306cebfbda2c520f545d36b5be2c7255cc528bb45d6/typing_extensions-4.16.0.tar.gz"
    sha256 "dc983d19a509c94dba722ee6abd33940f7c05a89e243c47e907eb4db6f1a43e5"
  end

  def install
    venv = virtualenv_create(libexec, "python3.12")
    # `virtualenv_install_with_resources` would run one `pip install` per
    # resource; batching them into a single call pays pip's startup once and
    # drops the build from ~18.5s to ~11.7s on this resource set.
    stage_resources(resources.to_a) { |dirs| venv.pip_install dirs }
    venv.pip_install_and_link buildpath
  end

  # Stage every resource at once and hand the directories to the block.
  # `Resource#stage` deletes its directory when its block returns, so the
  # stages have to nest — a loop collecting paths would hand `pip` ten
  # directories that no longer exist.
  def stage_resources(remaining, staged = [], &block)
    return yield(staged) if remaining.empty?

    remaining.first.stage { stage_resources(remaining.drop(1), staged + [Pathname.pwd], &block) }
  end

  def caveats
    <<~EOS
      One-time wiring (statusLine + Claude Code hooks/commands) is not done by
      brew. Run it once after install:
        cockpit setup

      Before uninstalling, remove those ~/.claude entries (brew leaves them):
        cockpit teardown

      No re-setup after `brew upgrade`: `cockpit watch` re-pins its interpreter
      on the next start.
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/cockpit --version")

    # `--version` proves nothing about the resources: cockpit imports lazily and
    # returns before touching textual, so it passes against a venv with none.
    # Must be the venv's interpreter and not PATH's, or this resolves against
    # system site-packages. `cockpit watch` can't serve — exits 2 with no TTY.
    system libexec/"bin/python", "-c", "import cockpit.tui.app"
  end
end
