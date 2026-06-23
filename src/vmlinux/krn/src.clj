(ns vmlinux.krn.src
  (:require [babashka.fs :as fs]
            [babashka.process :refer [shell]]
            [clojure.string :as str]))

(defrecord KernelSrc [tarball-url checksums-url])
(defrecord KernelTree [path checksum])

(defn- vdir [version] (str "v" (first (str/split version #"\.")) ".x"))

(defn- basename [url] (last (str/split url #"/")))

(defn- file-sha256
  [path]
  (-> (shell {:out :string} "sha256sum" (str path))
      :out
      (str/split #"\s+")
      first))

(defn- expected-sha256
  [checksums-url tarball-name]
  (let [text (:out (shell {:out :string} "curl" "-fsSL" checksums-url))
        suffix (str "  " tarball-name)
        line (->> (str/split-lines text)
                  (filter #(str/ends-with? % suffix))
                  first)]
    (when-not line
      (throw (ex-info (str "no sha256 for " tarball-name " on kernel.org")
                      {:tarball tarball-name})))
    (first (str/split (str/trim line) #"\s+"))))

(defn fetch-src
  [version]
  (let [base (str "https://cdn.kernel.org/pub/linux/kernel/" (vdir version))
        tarball (str "linux-" version ".tar.xz")]
    (->KernelSrc (str base "/" tarball) (str base "/sha256sums.asc"))))

(defn download
  [^KernelSrc src]
  (let [{:keys [tarball-url checksums-url]} src
        tarball (basename tarball-url)
        dir (str (fs/create-temp-dir {:prefix "vmlinux-krn-"}))
        tarball-path (str dir "/" tarball)
        expected-sum (expected-sha256 checksums-url tarball)]
    (shell "curl" "-fSL" tarball-url "-o" tarball-path)
    (let [actual (file-sha256 tarball-path)]
      (assert (= expected-sum actual)
              (str "sha256 mismatch for " tarball ": expected " expected-sum ", got " actual)))
    (shell {:dir dir} "tar" "-xf" tarball-path)
    (->KernelTree (str dir "/" (str/replace tarball #"\.tar\.xz$" "")) expected-sum)))
