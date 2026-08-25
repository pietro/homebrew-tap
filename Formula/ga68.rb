class Gcc < Formula
  desc "GNU compiler collection"
  homepage "https://gcc.gnu.org/"
  license "GPL-3.0-or-later" => { with: "GCC-exception-3.1" }
  head "https://gcc.gnu.org/git/gcc.git", branch: "master"

  stable do
    url "https://ftpmirror.gnu.org/gnu/gcc/gcc-16.2.0/gcc-16.2.0.tar.xz"
    mirror "https://ftp.gnu.org/gnu/gcc/gcc-16.2.0/gcc-16.2.0.tar.xz"
    sha256 "e6738e29597f733270731aa90600f37ffdc045079dfc27ec7e8192cc81085c3e"

    # Branch from the Darwin maintainer of GCC, with a few generic fixes and
    # Apple Silicon support, located at https://github.com/iains/gcc-16-branch
    patch do
      on_macos do
        file "Patches/gcc/gcc-16.2.0.diff"
      end
    end
  end

  livecheck do
    url :stable
    regex(%r{href=["']?gcc[._-]v?(\d+(?:\.\d+)+)(?:/?["' >]|\.t)}i)
  end

  # The bottles are built on systems with the CLT installed, and do not work
  # out of the box on Xcode-only systems due to an incorrect sysroot.
  pour_bottle? only_if: :clt_installed

  depends_on "gmp"
  depends_on "isl"
  depends_on "libmpc"
  depends_on "mpfr"
  depends_on "zstd"

  uses_from_macos "flex" => :build
  uses_from_macos "m4" => :build

  on_macos do
    # macOS make is too old, has intermittent parallel build issue
    depends_on "make" => :build
  end

  on_linux do
    depends_on "binutils"
    depends_on "zlib-ng-compat"
  end

  def version_suffix
    if build.head?
      "HEAD"
    else
      version.major.to_s
    end
  end

  def install
    # GCC will suffer build errors if forced to use a particular linker.
    ENV.delete "LD"

    languages = %w[algol68]

    pkgversion = "GNU Algol 68 GCC #{pkg_version}"

    # Use `lib/gcc/current` to provide a path that doesn't change with GCC's version.
    args = %W[
      --prefix=#{opt_prefix}
      --libdir=#{opt_lib}/gcc/current
      --disable-nls
      --enable-checking=release
      --with-gcc-major-version-only
      --enable-languages=#{languages.join(",")}
      --program-suffix=-#{version_suffix}
      --with-gmp=#{formula_opt_prefix("gmp")}
      --with-mpfr=#{formula_opt_prefix("mpfr")}
      --with-mpc=#{formula_opt_prefix("libmpc")}
      --with-isl=#{formula_opt_prefix("isl")}
      --with-zstd=#{formula_opt_prefix("zstd")}
      --with-pkgversion=#{pkgversion}
      --with-bugurl=#{tap.issues_url}
      --with-system-zlib
    ]

    if OS.mac?
      cpu = Hardware::CPU.arm? ? "aarch64" : "x86_64"
      args << "--build=#{cpu}-apple-darwin#{OS.kernel_version.major}"

      sdk = MacOS.sdk_path
      args << "--with-sysroot=#{sdk}" if sdk

      # Avoid this semi-random failure:
      # "Error: Failed changing install name"
      # "Updated load commands do not fit in the header"
      make_args = %w[
        BOOT_LDFLAGS=-Wl,-headerpad_max_install_names
        LDFLAGS_FOR_TARGET=-Wl,-headerpad_max_install_names
      ]
    else
      args << "--disable-multilib"
      args << "--with-linker-hash-style=gnu"

      # Enable to PIE by default to match what the host GCC uses
      args << "--enable-default-pie"

      # Change the default directory name for 64-bit libraries to `lib`
      # https://stackoverflow.com/a/54038769
      inreplace "gcc/config/i386/t-linux64", "m64=../lib64", "m64="
      inreplace "gcc/config/aarch64/t-aarch64-linux", "lp64=../lib64", "lp64="

      ENV.append_path "CPATH", formula_opt_include("zlib-ng-compat")
      ENV.append_path "LIBRARY_PATH", formula_opt_lib("zlib-ng-compat")
    end

    mkdir "build" do
      # Do not strip the binaries on macOS, it makes them unsuitable for loading plugins
      install_target = OS.mac? ? "install" : "install-strip"

      # To make sure GCC does not record cellar paths, we configure it with
      # opt_prefix as the prefix. Then we use DESTDIR to install into a
      # temporary location, then move into the cellar path.
      system "../configure", *args
      system "gmake", *make_args
      system "gmake", install_target, "DESTDIR=#{buildpath}/instdir"
      prefix.install buildpath.glob("instdir/#{opt_prefix}/*")
    end

    bin.install_symlink bin/"ga68-#{version_suffix}" => "ga68"

    # Provide a `lib/gcc/xy` directory to align with the versioned GCC formulae.
    # We need to create `lib/gcc/xy` as a directory and not a symlink to avoid `brew link` conflicts.
    (lib/"gcc"/version_suffix).install_symlink (lib/"gcc/current").children

    # Delete man pages and info files to avoid conflict with other GCC formulas.
    rm_r(man7)
    rm_r(info)
  end

  post_install_steps do
    configure_gcc_runtime

    # Remove gcc/g++ drivers to avoid conflict with other GCC formulas.
    remove("*gcc*", base: :bin)
    remove("*g++*", base: :bin)
    remove("*gcov*", base: :bin)
    remove("*lto*", base: :bin)
  end

  test do
    (testpath/"hello.a68").write <<~ALGOL68
      begin
           puts("Hello, world!'n");
      end
    ALGOL68
    system bin/"ga68", "-o", "hello-a68", "hello.a68"
    assert_equal "Hello, world!\n", shell_output("./hello-a68")
  end
end
