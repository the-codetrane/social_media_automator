# frozen_string_literal: true

module MediaAssets
  # Creates the blob record ahead of a browser → Spaces direct upload, filing
  # it under the folder the user picked in the upload modal. Mirrors
  # ActiveStorage::DirectUploadsController but sits behind the app's
  # authentication and lets us choose the blob key.
  class DirectUploadsController < ApplicationController
    def create
      folder = MediaAssetFolders.sanitize(params[:folder])
      return render json: { error: "Destination folder is required" }, status: :unprocessable_entity if folder.nil?

      blob = ActiveStorage::Blob.create_before_direct_upload!(key: MediaAssetFolders.key_for(folder), **blob_args)
      render json: direct_upload_json(blob)
    end

    private

    def blob_args
      params.expect(blob: [ :filename, :byte_size, :checksum, :content_type, metadata: {} ]).to_h.symbolize_keys
    end

    def direct_upload_json(blob)
      blob.as_json(root: false, methods: :signed_id).merge(direct_upload: {
        url: blob.service_url_for_direct_upload,
        headers: blob.service_headers_for_direct_upload
      })
    end
  end
end
