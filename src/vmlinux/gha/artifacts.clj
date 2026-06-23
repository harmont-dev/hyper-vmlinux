(ns vmlinux.gha.artifacts
  (:require
   [babashka.fs :as fs]
   [clojure.edn :as edn]
   [vmlinux.krn.build :as build]))

(defrecord VmLinuxArtifact [artifact-name])
(defrecord ArtifactMeta [name arch version binary sha256-sum])

(def ^:private stage-dir "out")

(defn- artifact-name [{:keys [name]}] (str "vmlinux-" name))

(defn prepare-artifact
  [{:keys [name arch version binary-path sha256-sum], :as vmlinux-build}]
  (let [art-name (artifact-name vmlinux-build)
        dir (str stage-dir "/" art-name)
        binary (fs/file-name binary-path)]
    (fs/create-dirs dir)
    (fs/copy binary-path (str dir "/" binary) {:replace-existing true})
    (spit (str dir "/meta.edn")
          (pr-str (into {} (->ArtifactMeta name arch version binary sha256-sum))))
    (->VmLinuxArtifact art-name)))

(defn load-artifact
  [dir]
  (let [am (map->ArtifactMeta (edn/read-string (slurp (str dir "/meta.edn"))))]
    (build/map->VmLinuxBuild {:name (:name am),
                              :arch (:arch am),
                              :version (:version am),
                              :binary-path (str dir "/" (:binary am)),
                              :sha256-sum (:sha256-sum am)})))
