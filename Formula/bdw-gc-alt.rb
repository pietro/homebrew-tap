# Based on https://github.com/pietro/homebrew-core/blob/main/Formula/b/bdwgc.rb
class BdwGcAlt < Formula
  desc "Garbage collector for C and C++"
  homepage "https://www.hboehm.info/gc/"
  url "https://github.com/bdwgc/bdwgc/releases/download/v8.2.12/gc-8.2.12.tar.gz"
  sha256 "42e5194ad06ab6ffb806c83eb99c03462b495d979cda782f3c72c08af833cd4e"
  license all_of: [
    "Boehm-GC",
    "HPND-sell-variant", # include/gc_allocator.h
  ]
  head "https://github.com/bdwgc/bdwgc.git", branch: "master"

  livecheck do
    url :stable
    strategy :github_latest
  end

  bottle do
    root_url "https://github.com/pietro/homebrew-tap/releases/download/bdw-gc-alt-8.2.12"
    sha256 cellar: :any, arm64_tahoe:   "b01cdfa767c5269812addba4ae62b4da89ac702db6544b80ef599ff2fd341cc1"
    sha256 cellar: :any, arm64_sequoia: "1275d86f6d0067735d263f7f8733d7a3bf46cb2432855cbb92c9e9e7391e5a7f"
    sha256 cellar: :any, tahoe:         "f56eaf6e3d17d0c4884a2b85495709fad76ec5dcafac602ebcc27dc5657f4523"
    sha256 cellar: :any, sequoia:       "3fa40957a91a2e2b917c0a8c4aeb1f9c10589b68c1ccac93080ae1501aada603"
    sha256 cellar: :any, arm64_linux:   "80b7b1ce6070c914c68b18974eea1b8822b451de0038b00daede8d79d23ffa65"
    sha256 cellar: :any, x86_64_linux:  "6a42625efa8edba1ae51dd079315b90c09b8affab096acfa3bd90725dfcb7468"
  end

  depends_on "cmake" => :build

  conflicts_with "bdw-gc",
  because: "same formula as homebrew-core, but woth bottles for x84_64 macos"

  def install
    args = %w[
      -Denable_cplusplus=ON
      -Denable_large_config=ON
      -Dwithout_libatomic_ops=OFF
      -Dwith_libatomic_ops=OFF
    ]

    system "cmake", "-S", ".", "-B", "build",
                    "-Dbuild_tests=ON",
                    "-DBUILD_SHARED_LIBS=ON",
                    "-DCMAKE_INSTALL_RPATH=#{rpath}",
                    *args, *std_cmake_args,
                    "-DBUILD_TESTING=ON" # Pass this *after* `std_cmake_args`
    system "cmake", "--build", "build"
    system "ctest", "--test-dir", "build",
                    "--parallel", ENV.make_jobs,
                    "--rerun-failed",
                    "--output-on-failure",
                    "--repeat", "until-pass:3"
    system "cmake", "--install", "build"

    system "cmake", "-S", ".", "-B", "build-static", "-DBUILD_SHARED_LIBS=OFF", *args, *std_cmake_args
    system "cmake", "--build", "build-static"
    lib.install buildpath.glob("build-static/*.a")
  end

  test do
    (testpath/"test.c").write <<~C
      #include <assert.h>
      #include <stdio.h>
      #include "gc.h"

      int main(void)
      {
        int i;

        GC_INIT();
        for (i = 0; i < 10000000; ++i)
        {
          int **p = (int **) GC_MALLOC(sizeof(int *));
          int *q = (int *) GC_MALLOC_ATOMIC(sizeof(int));
          assert(*p == 0);
          *p = (int *) GC_REALLOC(q, 2 * sizeof(int));
        }
        return 0;
      }
    C

    system ENV.cc, "test.c", "-I#{include}", "-L#{lib}", "-lgc", "-o", "test"
    system "./test"
  end
end
