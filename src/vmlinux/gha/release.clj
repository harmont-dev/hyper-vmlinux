(ns vmlinux.gha.release
  (:require
   [babashka.fs :as fs]
   [babashka.process :refer [shell]]
   [selmer.parser :as p]))

(defn- release-tag [sha] (str "release-" sha))

(defn- title [sha] (p/render "Hyper Firecracker Linux Images {{sha}}" {:sha sha}))

(defn- notes
  [sha]
  (p/render
   "VMLinux images used within [Hyper](https://github.com/harmont-dev/hyper) built off of `{{sha}}`."
   {:sha sha}))

(defn- asset-name
  [{:keys [arch version binary-path]}]
  (str (fs/file-name binary-path) "-" (name arch) "-" version))

(defn exists?
  [sha]
  (-> (shell {:continue true, :out :string, :err :string} "gh" "release" "view" (release-tag sha))
      :exit
      zero?))

(defn create
  [sha vmlinux-builds]
  (assert (not (exists? sha)) (str "release already exists: " (release-tag sha)))
  (let [tag (release-tag sha)]
    (shell "gh" "release" "create" tag "--title" (title sha) "--notes" (notes sha))
    (->> vmlinux-builds
         (mapv (fn [build]
                 (future (let [asset (str (fs/parent (:binary-path build)) "/" (asset-name build))]
                           (fs/copy (:binary-path build) asset {:replace-existing true})
                           (shell "gh" "release" "upload" tag asset)))))
         (run! deref))
    tag))
