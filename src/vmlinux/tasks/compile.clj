(ns vmlinux.tasks.compile
  (:require [manifest :as mf]
            [vmlinux.gha.artifacts :as artifacts]
            [vmlinux.krn.build :as kbuild]
            [vmlinux.krn.src :as src]))

(defn- by-name [name] (first (filter #(= name (:name %)) mf/builds)))

(defn build
  [name]
  (let [spec (or (by-name name) (throw (ex-info (str "no such target: " name) {:name name})))
        tree (src/download (src/fetch-src (:version spec)))
        out (kbuild/compile (:path tree) spec)]
    (artifacts/prepare-artifact out)))

(defn -main [& [name]] (println (str "built + staged " (:artifact-name (build name)))))
