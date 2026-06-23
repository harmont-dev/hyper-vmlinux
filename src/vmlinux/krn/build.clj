(ns vmlinux.krn.build
  (:refer-clojure :exclude [compile])
  (:require [babashka.fs :as fs]
            [babashka.process :refer [shell]]
            [clojure.string :as str]))

(defrecord VmLinuxBuild [arch version binary-path sha256-sum])

(defn- nproc [] (.availableProcessors (Runtime/getRuntime)))

(defn- file-sha256
  [path]
  (-> (shell {:out :string} "sha256sum" (str path))
      :out
      (str/split #"\s+")
      first))

(def ^:private arch-kbuild
  {:x86_64 {:kbuild-arch "x86_64", :target "vmlinux", :boot-subpath "vmlinux"},
   :aarch64 {:kbuild-arch "arm64", :target "Image", :boot-subpath "arch/arm64/boot/Image"}})

(defn compile
  [path {:keys [arch version config-file]}]
  (let [{:keys [kbuild-arch target boot-subpath]} (arch-kbuild arch)]
    (fs/copy (fs/absolutize config-file) (str path "/.config") {:replace-existing true})
    (shell {:dir path} "make" (str "ARCH=" kbuild-arch) "olddefconfig")
    (shell {:dir path} "make" (str "ARCH=" kbuild-arch) (str "-j" (nproc)) target)
    (let [binary (str path "/" boot-subpath)]
      (->VmLinuxBuild arch version binary (file-sha256 binary)))))
