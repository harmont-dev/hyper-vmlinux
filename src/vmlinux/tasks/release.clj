(ns vmlinux.tasks.release
  (:require [clojure.java.io :as io]
            [vmlinux.gha.artifacts :as artifacts]
            [vmlinux.gha.release :as release]))

(defn- artifact-dirs
  [dir]
  (->> (file-seq (io/file dir))
       (filter #(= "meta.edn" (.getName %)))
       (mapv #(str (.getParent %)))))

(defn load-artifacts [dir] (mapv artifacts/load-artifact (artifact-dirs dir)))

(defn -main [& [dir sha]] (println (str "published " (release/create sha (load-artifacts dir)))))
